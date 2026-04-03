# README – Environment Setup

## Task Environment Setup and Package Management

### Overview

This directory contains configuration files and package records for both R and Python environments used across the project. It ensures full reproducibility of the computational environment by defining exact Conda environments, recording installed package versions, and providing scripts for installation and verification.

---

### Directory Contents

| File | Description |
|---|---|
| `group10_python.yml` | Conda environment specification for Python, including all required Python dependencies |
| `group10_R.yml` | Conda environment specification for R, including R base and required system-level dependencies |
| `group10_kmedoids.yml` | Dedicated Conda environment for the K-Medoids pipeline. Created to resolve an incompatibility between `scikit-learn-extra` and `numpy` that arose in the main Python environment. To avoid affecting the rest of the pipeline, only the K-Medoids scripts (`10_Kmedoids/`) are run in this environment. |
| `python_packages.csv` | List of installed Python packages, used for reproducibility and auditing |
| `r_packages.csv` | List of installed R packages, including CRAN and manually installed packages |
| `packages.R` | R script to install required R packages, including CRAN and GitHub packages (e.g. missForestPredict) |
| `check_conda_r_packages.sh` | Script to verify installed R packages in the HPC environment |
| `check_conda_r_packages_report.sh` | Script to generate a summary report of installed R packages |
| `install_R_packages.out` | Output log from the R package installation job on HPC |
| `install_R_packages.err` | Error log from the R package installation job on HPC |
| `ReadMe.txt` | Original plain-text README for this directory |

---

### Workflow

#### 1. Environment Creation

**Python:**
```bash
conda env create -f group10_python.yml
```

**R:**
```bash
conda env create -f group10_R.yml
```

**K-Medoids (dedicated environment):**
```bash
conda env create -f group10_kmedoids.yml
```

#### 2. Package Installation

Run `packages.R` inside the R environment to install all required libraries. This script handles both CRAN packages and GitHub packages such as `missForestPredict`.

#### 3. Verification

Use the `check_conda_r_packages` scripts to confirm that all packages are correctly installed. Compare the output against `r_packages.csv` and `python_packages.csv` to detect version mismatches or missing packages.

#### 4. HPC Execution

Jobs are submitted via bash scripts. The `.out` and `.err` log files capture installation progress, warnings, errors, and system messages.

---

### Important Notes

- Always activate the correct environment before running any scripts with the Bash scripts:
  ```bash
  conda activate group10_python
  conda activate group10_R
  conda activate group10_kmedoids  # for K-Medoids scripts only
  ```
- The `group10_kmedoids` environment was created specifically to resolve a version incompatibility between `scikit-learn-extra` and `numpy` in the main Python environment. All scripts in the `10_Kmedoids/` pipeline step must be run in this dedicated environment; all other Python scripts should use `group10_python`.
- The CSV package lists serve as a reference for auditing, not as installation scripts
- The `prefix` field specifying absolute installation paths has been removed from the YAML files to allow environments to be recreated flexibly within each user's own directory and avoid path-related conflicts
- Check the `.err` log files if installation fails, packages are missing, or version mismatches occur

---

End of file