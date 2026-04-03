README.txt

Task Overview:
Task 1: UKB Preprocessing Pipeline
Task 2: UKB Missingness and Prefer Not To Answer (PNTA) Filtering Pipeline


Task 1: UKB Preprocessing Pipeline

Required R packages:
- dplyr
- tibble
- stringr

## Directory Structure

1. script/

   * Contains R scripts for preprocessing.
   * Main script performs:
     • variable selection and canonical renaming
     • repeated-measure aggregation
     • quality control and range cleaning
     • recoding of categorical variables
     • derived feature construction
     • domain-specific preprocessing
     • final dataset assembly

2. log/

   * Contains HPC execution logs.
   * Includes:
     • job runtime and resource usage
     • console messages during preprocessing
     • warnings or errors for debugging

3. output/

   * Contains processed dataframes and related outputs.
   * Main output includes:
     • ukb_processed.rds

## Script Description

Input:

* Raw UK Biobank dataset:
  • ukb_raw.rds

Output:

* Preprocessed dataset:
  • ukb_processed.rds

Processing Steps:

1. Load Data

   * Read the raw UK Biobank dataset from ukb_raw.rds.

2. Variable Mapping and Canonical Feature Construction

   * Use a predefined rule table to map raw variable names into standardized canonical names.
   * Match both synthetic and real variable base names.
   * For repeated measurements:
     • numeric variables are averaged across available columns
     • categorical variables keep the first non-missing value

3. Derived Core Variables

   * Create combined variables such as:
     • bmi
     • systolic_bp
     • diastolic_bp

4. Quality Control and Range Cleaning

   * Apply plausible-value checks to anthropometric, ECG, pulse wave analysis, pulmonary, sleep, and laboratory variables.
   * Values outside valid ranges are set to NA.

5. Cancer Feature Engineering

   * Create cancer indicator/count variables from cancer_code fields:
     • lung_cancer
     • liver_cancer
     • kidney_cancer

6. Diet and Lifestyle Processing

   * Recode diet, alcohol, physical activity, and smoking variables.
   * Create derived variables such as:
     • total_unit_alcohol_per_week
     • MET_total
     • HSI
     • pack_year_index
     • DASH_score

7. Domain-Specific Preprocessing

   * Build cleaned variables for multiple domains, including:
     • social support
     • socioeconomic status
     • mental health
     • addiction
     • health/comorbidities
     • occupational exposure

8. Scoring and Recoding

   * Convert categorical responses such as:
     • Yes / No
     • Prefer not to answer
     • Do not know
   * Recode them into analysis-ready numeric or categorical forms.
   * Construct summary scores such as:
     • social_support_score
     • anxiety_score
     • depression_score
     • sleep_symptom_count

9. Final Cleanup

* Remove redundant raw variables and temporary score components.
* Standardize column names.
* Save the final processed dataframe.

## Methods Used

* Rule-Based Variable Mapping:
  Standardizes raw UKB variable names into canonical features.

* Repeated-Measure Aggregation:
  Uses row means for numeric repeated measures and first non-missing value for categorical repeated measures.

* Quality Control Filtering:
  Applies predefined valid ranges to detect implausible values and replace them with NA.

* Categorical Recoding:
  Converts text-based survey responses into numeric analysis-ready formats.

* Feature Engineering:
  Builds derived clinical, lifestyle, and domain-specific variables from raw inputs.

* Domain Integration:
  Combines multiple related variables into cleaner summary features for downstream analysis.

## Notes

* The script is designed to prepare raw UKB data for downstream filtering, imputation, and modeling.
* “Prefer not to answer” is often retained as -1, while “Do not know” is usually converted to NA.
* Repeated raw fields are collapsed into single canonical variables where appropriate.
* Out-of-range values are treated as invalid and set to NA rather than removed entirely.

==========================================================================
Task 2: UKB Missingness and Prefer Not To Answer (PNTA) Filtering Pipeline
==========================================================================

Required R packages:
- dplyr
- ggplot2
- gridExtra


## Directory Structure

1. script/

   * Contains R scripts for NA filtering and removal.
   * Main script performs:
     • PNTA (-1) screening
     • Missingness filtering
     • Participant filtering
     • Variable filtering
     • Restoration of selected clinical and lifestyle variables
     • Generation of filtering plots

2. log/

   * Contains HPC execution logs.
   * Includes:
     • job submission and runtime records
     • memory and CPU usage
     • console outputs from each filtering step
     • debugging or error messages when applicable

3. output/

   * Contains filtered dataframes and plots.
   * Includes:
     • ukb_filtered_NA.rds
     • ukb_filtering_plots.png

## Script Description

Input:

* Processed UK Biobank dataset:
  • ukb_processed.rds

Output:

* Filtered dataset:
  • ukb_filtered_NA.rds
* Filtering visualization:
  • ukb_filtering_plots.png

Processing Steps:

1. Load Data

   * Read the processed dataset from ukb_processed.rds
   * Convert to data.frame
   * Recover or create the eid column if needed
   * Check that eid is unique for all participants

2. PNTA Filtering by Variable

   * Identify variables with excessive "Prefer Not To Answer" values coded as -1
   * Exclude eid from screening
   * Use an elbow-based threshold to determine which variables should be removed

3. PNTA Filtering by Participant

   * Remove participants who still have any remaining -1 values after variable filtering
   * Exclude eid from screening

4. Missingness Filtering by Variable

   * Calculate the percentage of missing values in each variable
   * Exclude eid from screening
   * Use an elbow-based threshold to remove variables with excessive missingness

5. Missingness Filtering by Participant

   * Calculate the percentage of missing values for each participant
   * Remove participants with excessive missingness
   * Exclude eid from screening

6. Add Back Selected Variables

   * Reintroduce selected variables from the original dataset using eid matching
   * These include:
     • BHI-related variables
     • CVHI-related variables
     • smoking variables
     • alcohol variables
     • physical activity variables
   * Keep NA values in these returned columns
   * Remove participants with any -1 values in the added-back selected columns

7. Generate Plots

   * Create elbow plots for:
     • PNTA by variable
     • Missingness by variable
     • Missingness by participant
   * Save combined plot as ukb_filtering_plots.png

8. Save Final Output

   * Save the final filtered dataset as ukb_filtered_NA.rds

## Methods Used

* PNTA Screening:
  Variables and participants are screened for "Prefer Not To Answer" values coded as -1.

* Missingness Filtering:
  Variables and participants are filtered based on missing data percentages.

* Elbow Method:
  The cutoff for removing variables or participants is determined using an elbow-detection algorithm based on maximum perpendicular distance from the ranked curve.

* Visualization:
  ggplot2 and gridExtra are used to generate and combine filtering plots.

## Notes

* eid is treated as the participant identifier and is protected from filtering steps.
* The script removes both high-PNTA and high-missingness variables/participants before restoring selected variables.
* Added-back variables are allowed to retain NA values, but participants with -1 in these selected variables are removed.
* The final output is intended for downstream imputation and analysis.


End of README
