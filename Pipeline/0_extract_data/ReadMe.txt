README.txt

Task 1: UKB Data Dictionary Generation Pipeline
Task 2: UKB Variable Extraction Pipeline
Task 3: UKB Variable Recoding Pipeline
Task 4: UKB CVD Outcome Construction Pipeline

Required R packages:
- dplyr
- data.table
- openxlsx

Task 1: UKB Data Dictionary Generation Pipeline
---

## Directory Structure

1. script/

   * Contains R scripts for generating a data dictionary.
   * Main script performs:
     • extraction of variable IDs from UK Biobank dataset
     • matching with official UKB data dictionary
     • creation of a structured variable reference table
     • generation of an editable Excel file for downstream use

2. log/

   * Contains HPC execution logs.
   * Includes:
     • job submission and runtime records
     • console outputs 
     • debugging or error messages when applicable

3. output/ (or parameters/)

   * Contains generated data dictionary files.
   * Includes:
     • selection.xlsx (main output)
     
---

## Script Description

Input:

* UK Biobank dataset (column structure only):
  • input file path provided as command-line argument (ukb_path)

* UK Biobank Data Dictionary:
  • ../docs/Data_Dictionary_Showcase.csv

Output:

* Data dictionary Excel file:
  • ../parameters/selection.xlsx

Processing Steps:

1. Load Data

   * Read column names from the UKB dataset (without loading full data).
   * Load the official UK Biobank data dictionary.

2. Extract Field IDs

   * Parse column names to extract unique FieldIDs.
   * Remove instance and array suffixes (e.g., "-0.0").
   * Identify unmatched FieldIDs and print them for validation.

3. Match with UKB Data Dictionary

   * Filter the official dictionary to include only variables present in the dataset.
   * Retain key metadata columns:
     • Field, Participants, Notes, Units, Path, Link, FieldID, ValueType, Coding

4. Add Custom Annotation Columns

   * Create empty columns for manual annotation.    
     • CodingName 
     • FigureName 
     • UnitInName 
     • InstanceList 

5. Detect Available Instances

   * For each variable:
     • scan dataset column names
     • extract available instance indices.
   * Store results in InstanceList

6. Define Instance Selection

   * By default, keep all available instances
   * Allow manual modification via InstanceRequired column

7. Reorganize Table Structure

   * Arrange columns in a logical and user-friendly order
   * Prepare for downstream preprocessing and feature engineering

8. Export Output

   * Save the final data dictionary as an Excel file:
     • selection.xlsx
   * Apply formatting:
     • freeze header row and first column

---

## Methods Used

* ID Extraction:
  String processing using gsub and pattern matching

* Dictionary Matching:
  Filtering based on FieldID intersection

* Instance Detection:
  Parsing UKB column naming structure (FieldID-instance-array)

* Data Handling:
  Efficient loading using data.table

* Output Generation:
  Excel export using openxlsx

---

## Notes

* The generated Excel file is intended for manual curation and variable selection.
* This step is critical for standardizing variable naming before preprocessing and modeling.

---

Task 2: UKB Variable Extraction Pipeline

---

## Directory Structure

1. script/

   * Contains R scripts for extracting selected variables from UK Biobank.
   * Main script performs:
     • reading selected variables from data dictionary
     • extracting specified variables and instances
     • applying standardized variable naming
     • generating coding templates for recoding

2. log/

   * Contains HPC execution logs.
   * Includes:
     • job submission and runtime records
     • console outputs (selected variables, progress bars)
     • debugging or error messages when applicable

3. output/

   * Contains extracted datasets and supporting files.
   * Includes:
     • ukb_extracted.rds (main extracted dataset)
     • annot.rds (variable metadata and annotations)
     • ../parameters/codings/ (coding reference files)

---

## Script Description

Input:

* UK Biobank dataset:
  • input file path provided as argument (ukb_path)

* Variable selection file:
  • ../parameters/selection.xlsx

* UK Biobank coding reference:
  • ../docs/Codings.csv

Output:

* Extracted dataset:
  • ../outputs/ukb_extracted.rds

* Variable annotation file:
  • ../outputs/annot.rds

* Coding reference files:
  • ../parameters/codings/codes_*.txt
  • ../parameters/codings/codes_template_continuous.txt

Processing Steps:

1. Prepare Output Directories

   * Create output and coding folders
   * Remove previous outputs to ensure clean execution

2. Load Variable Selection

   * Read selection.xlsx containing:
     • CodingName (variable name for analysis)
     • FigureName (display name)
     • InstanceRequired (time points to extract)

3. Validate Selection

   * Ensure no duplicated CodingName values
   * Print selected variables and instances

4. Extract Variables from UKB Dataset

   * Identify relevant columns using:
     • FieldID
     • selected instances (e.g., 0,1,2)
   * Load only selected columns (memory efficient)

5. Reformat Dataset

   * Set eid as row identifier
   * Rename variables using CodingName + instance suffix
   * Standardize column naming for downstream analysis

6. Generate Coding Files

   * Extract categorical coding schemes from Codings.csv
   * Save individual coding files for each variable
   * Create template file for continuous variable recoding

7. Generate Figure Names

   * Use FigureName if provided
   * Otherwise fallback to original Field name
   * Optionally append units to names

8. Save Outputs

   * Save extracted dataset (ukb_extracted.rds)
   * Save annotation metadata (annot.rds)

---

## Methods Used

* Variable Selection:
  Based on manually curated data dictionary (selection.xlsx)

* Column Extraction:
  Pattern matching using FieldID and instance indices

* Coding System:
  Integration with UK Biobank coding reference for categorical variables

* Naming Standardization:
  Mapping to CodingName for analysis and FigureName for reporting

---

## Notes

* Only variables with non-NA CodingName are extracted.
* Instance selection allows flexible handling of longitudinal data.
* This step ensures clean, analysis-ready datasets for downstream pipelines.

---

Task 3: UKB Variable Recoding Pipeline

---

## Directory Structure

1. script/

   * Contains R scripts for recoding extracted UK Biobank variables.
   * Main script performs:
     • recoding categorical variables using UKB coding files
     • converting continuous variables to numeric
     • handling date/time/text variables
     • updating metadata for downstream selection

2. log/

   * Contains HPC execution logs.
   * Includes:
     • job submission and runtime records
     • console outputs (progress bars, warnings)
     • debugging or error messages when applicable

3. output/

   * Contains recoded datasets and updated metadata.
   * Includes:
     • recoded.rds (final recoded dataset)
     • ../parameters/parameters.xlsx (updated metadata with array info)

---

## Script Description

Input:

* Extracted dataset:
  • ../outputs/ukb_extracted.rds

* Variable annotation file:
  • ../outputs/annot.rds

* Coding reference files:
  • ../parameters/codings/codes_*.txt

Output:

* Recoded dataset:
  • ../outputs/recoded.rds

* Updated parameter file:
  • ../parameters/parameters.xlsx

Processing Steps:

1. Load Data

   * Load extracted dataset (ukb_extracted.rds)
   * Load variable annotations (annot.rds)

2. Initialize Recoding Process

   * Create a copy of the dataset for recoding
   * Initialize tracking for variables with incomplete coding

3. Recode Variables (Column-wise Loop)

   * For each variable:
     • identify corresponding CodingName and Coding ID
     • load coding file if available
     • map original values → recoded meanings

4. Categorical Variable Handling

   * Convert variables into factors
   * Order levels based on RecodedValue
   * Detect and report categories missing from coding files

5. Continuous and Integer Handling

   * Convert numeric-like variables to numeric type
   * Preserve original values if recoding is incomplete

6. Date / Time / Text Handling

   * Convert:
     • date variables → Date format
     • text/time/compound variables → character

7. Continuous Variable Binning (Optional)

   * Detect user-defined continuous coding files
   * Apply range-based binning using:
     • MinValue / MaxValue
   * Convert into ordered categorical variables

8. Quality Checks

   * Report variables with unmatched categories
   * Print frequency tables after recoding

9. Array Information Extraction

   * Identify available array indices per variable
   * Store in:
     • ArrayList
     • ArrayMethod (default settings)

10. Save Outputs

* Save updated metadata (parameters.xlsx)
* Save final recoded dataset (recoded.rds)

---

## Methods Used

* Mapping-Based Recoding:
  Using lookup tables (codes_*.txt) for categorical variables

* Type Conversion:
  Automatic detection and conversion based on ValueType

* Range-Based Binning:
  Continuous variables recoded using interval thresholds

* Data Integrity Checks:
  Detection of unmatched categories and validation outputs

* Metadata Integration:
  Updating annotation file with array and selection information

---

## Notes

* Recoding depends on completeness of coding files; missing mappings are reported.
* Continuous recoding requires manual definition of bins.
* Factor level ordering is preserved based on coding definitions.
* This step standardizes variables for downstream modeling and analysis.

---

Task 4: UKB CVD Outcome Construction Pipeline

---

## Directory Structure

1. script/

   * Contains R scripts for merging recoded UK Biobank data with CVD event data.
   * Main script performs:
     • loading recoded dataset
     • loading and cleaning CVD event records
     • merging datasets by participant ID (eid)
     • generating binary CVD outcome variable
     • basic data integrity checks

2. log/

   * Contains HPC execution logs.
   * Includes:
     • job runtime and resource usage
     • printed dataset dimensions
     • CVD distribution summaries
     • duplicate ID checks and debugging messages

3. output/

   * Contains processed datasets for downstream analysis.
   * Includes:
     • ukb_raw.rds (final dataset with CVD outcome and event date)

---

## Script Description

Input:

* Recoded dataset:
  • ../outputs/recoded.rds

* CVD event dataset:
  • /rds/.../cvd_events.rds

Output:

* Final merged dataset:
  • ukb_raw.rds

Processing Steps:

1. Load Data

   * Load recoded dataset
   * Convert rownames into eid column
   * Ensure eid is the first column

2. Load and Clean CVD Events

   * Load CVD event dataset
   * Rename date column → cvd_date
   * Convert to Date format
   * Sort by eid and cvd_date
   * Keep only the first (earliest) CVD event per participant

3. Merge Datasets

   * Perform left join using eid
   * Add cvd_date to recoded dataset

4. Create Outcome Variable

   * Generate binary outcome:
     • cvd = 1 → participant has CVD event
     • cvd = 0 → no CVD event
   * Place cvd and cvd_date after eid column

5. Sanity Checks

   * Count number of CVD=0 and CVD=1
   * Verify total number of rows
   * Check for duplicated eid in CVD dataset

6. Save Output

   * Save final dataset as ukb_raw.rds

---

## Notes

* Only the first CVD event per participant is retained.
* Participants without a CVD event are labeled as cvd = 0 and vice versa.
* This dataset serves as the foundation for downstream modeling and analysis.
* Ensure consistency of eid format across datasets before merging.

---

## End of README