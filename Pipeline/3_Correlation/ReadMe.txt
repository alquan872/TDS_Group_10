README.txt

Task: Correlation Analysis Pipeline (UK Biobank Imputed Data)

---
Required R packages:
- dplyr
- ggplot2
- corrplot

## Directory Structure

1. script/

   * Contains R scripts for correlation analysis and feature filtering.
   * Main script performs mixed-type association analysis and feature selection.

2. log/

   * Contains HPC execution logs.
   * Includes job runtime information, memory usage, and execution status.

3. output/

   * Contains generated datasets and visualizations.
   * Includes:
     • Mixed association heatmap (PNG)
     • Filtered datasets (CSV / RDS)
     • Correlation-based feature selection results

---

## Script Description

Input:

* Imputed UK Biobank datasets:
  • ukb_imputed_all.rds
  • ukb_train_imputed.rds
  • ukb_val_imputed.rds
  • ukb_test_imputed.rds

Processing Steps:

1. Data Preparation

   * Load imputed dataset
   * Identify protected variables (e.g., cvd)
   * Classify variables into:
     • numeric
     • categorical
     • index (if applicable)

2. Data Cleaning

   * Convert variable types appropriately
   * Remove:
     • zero-variance numeric variables
     • single-level categorical variables

3. Correlation / Association Analysis

   * Numeric vs Numeric → Pearson correlation
   * Categorical vs Categorical → Cramer's V
   * Numeric vs Categorical → Eta (correlation ratio)

4. Mixed Association Matrix

   * Combine all association types into one matrix
   * Remove variables with invalid values (NA / NaN / Inf)

5. Visualization

   * Generate clustered heatmap using corrplot
   * Output file:
     • mixed_association_heatmap.png

6. Feature Selection (Correlation-Based)

   * Identify strongly associated variable pairs (thresholds ≥ 0.5, 0.7, 0.9)
   * Drop predefined highly correlated variables
   * Additionally remove:
     • CVH-related scores
     • BHS-related scores

7. Output Generation

   * Save filtered datasets:
     • ukb_all_drop_correlation_score (CSV / RDS)
     • ukb_train_drop_correlation_score (CSV / RDS)
     • ukb_val_drop_correlation_score (CSV / RDS)
     • ukb_test_drop_correlation_score (CSV / RDS)

---

## Methods Used

* Pearson Correlation:
  Measures linear relationships between numeric variables.

* Cramer's V:
  Measures association strength between categorical variables.

* Eta (Correlation Ratio):
  Measures association between numeric and categorical variables.

* Hierarchical Clustering:
  Used in heatmap visualization to group similar variables.

---

## Notes

* This pipeline assumes input datasets are already imputed.

---

## End of README
