README.txt

Task: UKB Imputation Pipeline

---
Required R packages:
- randomForest
- missForestPredict
- dplyr
- data.table

## Directory Structure

1. script/

   * Contains R scripts for imputation.
   * Main script performs:
     • variable type classification
     • stratified train/validation/test splitting
     • Random Forest-based missing data imputation
     • post-imputation constraints and checks
     • CVH and BHS score generation
     • export of final datasets

2. log/

   * Contains HPC execution logs.
   * Includes:
     • job submission and runtime records
     • memory and CPU usage
     • missForest iteration output
     • console messages for checks and summaries
     • debugging or error messages when applicable

3. output/

   * Contains imputed dataframes and related outputs.
   * Includes:
     • ukb_train_imputed.rds
     • ukb_val_imputed.rds
     • ukb_test_imputed.rds
     • ukb_imputed_all.rds
     • ukb_train_imputed.csv
     • ukb_val_imputed.csv
     • ukb_test_imputed.csv
     • ukb_imputed_all.csv

---

## Script Description

Input:

* Filtered UK Biobank dataset:
  • ukb_filtered_NA.rds

Output:

* Imputed training dataset:
  • ukb_train_imputed.rds / ukb_train_imputed.csv
* Imputed validation dataset:
  • ukb_val_imputed.rds / ukb_val_imputed.csv
* Imputed test dataset:
  • ukb_test_imputed.rds / ukb_test_imputed.csv
* Combined imputed dataset:
  • ukb_imputed_all.rds / ukb_imputed_all.csv

Processing Steps:

1. Load Data

   * Read the filtered dataset from ukb_filtered_NA.rds.
   * Remove selected columns not used for imputation, such as cancer_histology.

2. Protect Key Variables

   * Keep selected variables separate from imputation, including:
     • date_of_death
     • cvd
     • eid

3. Automatic Variable Classification

   * Classify variables into:
     • numeric
     • categorical
     • index
   * Classification is based on:
     • variable data type
     • number of unique values
     • variable name patterns such as _score and HSI
     • forced numeric patterns such as _z_score and energy

4. Build Analysis Dataset

   * Construct the dataset used for splitting and imputation.
   * Convert categorical variables to factor.
   * Convert numeric and index variables to numeric type.

5. Stratified Data Splitting

   * Split the dataset into:
     • 70% training
     • 15% validation
     • 15% test
   * Stratified by cvd to preserve class balance.

6. Missing Data Imputation

   * Fit missForestPredict on the training analysis dataset only.
   * Apply the trained imputation model to validation and test datasets.
   * Extract imputed data from the returned missForest object structure.

7. Post-Imputation Processing

   * Constrain selected index variables to valid integer ranges:
     • DASH_score: 0–40
     • HSI: 0–6
   * Restore categorical variables as factors.

8. Rebuild Final Datasets

   * Bind protected variables back to imputed analysis data.
   * Add a data_type column for train, validation, and test.
   * Merge all subsets into a combined imputed dataset.

9. Final Data Checks

   * Confirm dataset dimensions.
   * Check whether missing values remain.
   * Review index ranges after post-imputation constraints.

10. Score Construction

* Derive CVH scores using thresholds estimated from the training set only.
* Derive BHS scores using training-set quartile thresholds for selected biomarkers and physiological measures.
* Apply the same thresholds consistently to validation and test sets.

11. Save Outputs

* Remove helper columns such as data_type and eid before export.
* Save final datasets in both RDS and CSV formats.

---

## Methods Used

* Automatic Variable Classification:
  Variables are assigned to numeric, categorical, or index groups using data type, name patterns, and unique-value counts.

* Stratified Sampling:
  The dataset is split by outcome class to preserve the cvd distribution across training, validation, and test sets.

* Random Forest Imputation:
  Missing values are imputed using missForestPredict, trained only on the training set and then applied to validation and test data.

* Post-Imputation Constraint Rules:
  Selected index variables are clipped to valid ranges and rounded where needed.

* Train-Based Thresholding:
  CVH and BHS scoring thresholds are derived from the training set only to reduce data leakage.

---

## Notes

* The script is designed for downstream corrleation analysis after missingness filtering.
* Imputation is trained on the training set only and then transferred to validation and test sets.
* Protected variables are excluded from imputation and reattached afterward.
* Final outputs are provided in both RDS and CSV formats for compatibility with later analysis steps.

---

## End of README
