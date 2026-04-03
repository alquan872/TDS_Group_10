README.txt

Task: UKB Table 1

---

## Directory Structure

1. scripts/

   * Contains R scripts for Table 1 generation.
   * Main script performs:
     • loading the imputed dataset
     • variable renaming for display
     • creation of full Table 1
     • creation of a key-variables Table 1
     • p-value calculation for group comparison
     • export of table objects and file manifests

2. logs/

   * Contains HPC execution logs.
   * Includes:
     • job submission and runtime records
     • console output during table generation
     • session information for reproducibility
     • debugging or error messages when applicable

3. outputs/

   * Contains generated table objects and related outputs.
   * Includes:
     • tables/table1_result.rds
     • tables/table1_result_key_variables.rds
     • tables/saved_files_manifest.txt
     • logs/session_info.txt

---

## Script Description

Input:

* Imputed UK Biobank dataset:
  • ukb_imputed_all.csv

Output:

* Full Table 1 object:
  • table1_result.rds
* Key-variables Table 1 object:
  • table1_result_key_variables.rds
* Saved files manifest:
  • saved_files_manifest.txt
* Session information log:
  • session_info.txt

Processing Steps:

1. Set Working Directory

   * Automatically detect script location in both non-interactive HPC runs and interactive RStudio sessions.

2. Prepare Output Folders

   * Define paths for input data, tables, and logs.
   * Recreate output folders before running.

3. Load Data

   * Read the imputed dataset from ukb_imputed_all.csv.
   * Print the dataset dimensions.

4. Variable Renaming for Presentation

   * Apply a display-name mapping so variables appear with publication-style labels in the generated tables.
   * Skip variables not found in the dataset.

5. Full Table 1 Generation

   * Convert selected variables such as sex and cvd into factors.
   * Build a Table 1 stratified by CVD status.
   * Summarize:
     • continuous variables as mean (SD)
     • categorical variables as N (%)
   * Add p-values for group comparison.

6. Key Variables Table Generation

   * Build a second Table 1 using a selected subset of clinically important variables.
   * Stratify again by CVD status.
   * Apply the same summary and p-value rules.

7. Save Outputs

   * Save both table objects as RDS files.
   * Save session information for reproducibility.
   * Save a manifest listing all generated files.

---

## Methods Used

* Table 1 Summary:
  Generated using the R table1 package.

* Continuous Variable Rendering:
  Continuous variables are summarized as mean (SD).

* Categorical Variable Rendering:
  Categorical variables are summarized as counts and percentages.

* Group Comparison:
  P-values are calculated by:
  • t-test for numeric variables
  • chi-square test for categorical variables

* Reproducibility Logging:
  sessionInfo() is saved to document the R environment and package versions.

---

## Notes

* The script uses the imputed combined dataset as input.
* Output tables are stratified by CVD status only.

---

## End of README
