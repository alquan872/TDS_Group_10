README.txt

Task: UKB Pipeline - Bash Execution Scripts Overview

---

## Directory Structure

1. script/

   * Contains Bash scripts used to run the full pipeline on HPC.
   * Includes:
     • individual job scripts (R / Python execution)
     • launcher scripts for pipeline stages
     • dependency-controlled job submission 
---

## Script Description (Bash Overview)

The Bash scripts are designed to orchestrate the full UK Biobank pipeline on an HPC cluster using PBS job scheduling.

Key Functionalities:

1. HPC Job Submission (PBS)

   * Each script defines resource requirements:
     • walltime (runtime limit)
     • CPU cores (ncpus)
     • memory (mem)

2. Environment Setup

   * Activate conda environments before execution:
     • R environment (group10_R)
     • Python environment (group10_python)

3. Script Execution

   * Run R or Python scripts in each section via:
     • Rscript for statistical pipelines
     • python3 for machine learning models

4. Logging System

   * Redirect outputs to log files:
     • PBS .out / .err files

5. Pipeline Automation (Launcher Scripts)

   * Use qsub to submit sequential jobs
   * Control execution order using dependencies:
     • -W depend=afterok:<JOB_ID>

6. Directory Management

   * Automatically create required folders before execution:
     • logs/
     • output/


7. Modular Pipeline Design

   * Pipeline is divided into stages:
     • data extraction & recoding
     • preprocessing & NA filtering
     • imputation & Table 1
     • correlation & univariate analysis
     • LASSO feature selection
     • XGBoost modeling
     • DAG plotting
     • clustering & deep learning

   * Each stage can be run independently or chained via launcher scripts.

---

## Methods Used

* Job Scheduling:
  PBS (Portable Batch System) 

* Dependency Control:
  Sequential execution using afterok conditions

* Environment Management:
  Conda environments for reproducible execution

* Logging:
  Combined PBS logs and custom runtime logs

* Pipeline Design:
  Modular + staged execution with launcher scripts

---

## Notes

* All scripts assume execution within an HPC environment.
* Launcher scripts are recommended for full pipeline runs.
* Individual scripts can be executed separately for debugging or partial runs.

---

## End of README
