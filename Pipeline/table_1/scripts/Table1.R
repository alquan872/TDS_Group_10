if (!interactive()) {
  setwd(dirname(normalizePath(commandArgs(trailingOnly=FALSE)[grep("--file=",commandArgs(trailingOnly=FALSE))][1] |> sub("--file=","",x=_))))
}
if (interactive()) {
  setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
}

DATA_DIR  <- "../../2_Imputation/outputs"
TABLE_DIR <- "../outputs/tables"
LOG_DIR   <- "../outputs/logs"

for (d in c(TABLE_DIR, LOG_DIR)) {
  if (dir.exists(d)) unlink(d, recursive = TRUE)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

suppressPackageStartupMessages({
  library(dplyr)
  library(table1)
  library(purrr)
  library(scales)
})

# load data
ukb <- read.csv(file.path(DATA_DIR, "ukb_imputed_all.csv"))
cat("Loaded:", nrow(ukb), "rows,", ncol(ukb), "cols\n")

# rename map: display name = column name
rename_map <- c(
  "Gender, N(%)" = "sex",
  "Age at recruitment (years), mean(SD)" = "age_at_recruitment",
  "Fat-free mass (kg), mean(SD)" = "fat_free_mass",
  "Body fat (%), mean(SD)" = "body_fat_pct",
  "Basal metabolic rate, mean(SD)" = "bmr",
  "Resting heart rate (beats/min), mean(SD)" = "ecg_heart_rate",
  "ECG load, mean(SD)" = "ecg_load",
  "Fitness bicycle speed, mean(SD)" = "fitness_bicycle_speed",
  "ECG phase time, mean(SD)" = "ecg_phase_time",
  "Cardiac pulse rate, mean(SD)" = "cardiac_pulse_rate",
  "PWA reflection index, mean(SD)" = "pwa_reflection_index",
  "PWA peak position, mean(SD)" = "pwa_peak_position",
  "PWA notch position, mean(SD)" = "pwa_notch_position",
  "Energy, mean(SD)" = "energy",
  "FEV1 best, mean(SD)" = "resp_fev1_best",
  "FVC best, mean(SD)" = "resp_fvc_best",
  "FEV1 z-score, mean(SD)" = "resp_fev1_z_score",
  "FVC z-score, mean(SD)" = "resp_fvc_z_score",
  "FEV1/FVC ratio z-score, mean(SD)" = "resp_fev1_fvc_ratio_z_score",
  "ECG during exercise duration, mean(SD)" = "ecg_during_exercise_duration",
  "Maximum workload, mean(SD)" = "fitness_workload_max",
  "IGF-1, mean(SD)" = "igf1",
  "Creatinine (µmol/L), mean(SD)" = "creatinine",
  "Aspartate aminotransferase, mean(SD)" = "aspartate_aminotransferase",
  "Alanine aminotransferase, mean(SD)" = "alanine_aminotransferase",
  "White blood cell count, mean(SD)" = "blood_wbc_count",
  "Red blood cell count, mean(SD)" = "blood_rbc_count",
  "Hemoglobin concentration, mean(SD)" = "blood_hemoglobin_conc",
  "Hematocrit (%), mean(SD)" = "blood_hematocrit_pct",
  "Platelet count, mean(SD)" = "blood_platelet_count",
  "Mean platelet volume, mean(SD)" = "blood_platelet_volume_mean",
  "Platelet distribution width, mean(SD)" = "blood_platelet_distribution_width",
  "Reticulocyte (%), mean(SD)" = "blood_reticulocyte_pct",
  "Reticulocyte count, mean(SD)" = "blood_reticulocyte_count",
  "Mean reticulocyte volume, mean(SD)" = "blood_reticulocyte_volume_mean",
  "Immature reticulocyte fraction, mean(SD)" = "blood_reticulocyte_immature_fraction",
  "High light scatter reticulocyte count, mean(SD)" = "blood_reticulocyte_hls_count",
  "Apolipoprotein A, mean(SD)" = "biochem_apoa",
  "Apolipoprotein B, mean(SD)" = "biochem_apob",
  "Total cholesterol (mmol/L), mean(SD)" = "biochem_cholesterol",
  "Serum glucose (mmol/L), mean(SD)" = "biochem_glucose",
  "HbA1c (%), mean(SD)" = "biochem_hba1c",
  "HDL cholesterol (mmol/L), mean(SD)" = "biochem_hdl",
  "LDL cholesterol (mmol/L), mean(SD)" = "biochem_ldl_direct",
  "Triglycerides (mmol/L), mean(SD)" = "biochem_triglycerides",
  "Urinary sodium, mean(SD)" = "biochem_sodium_urine",
  "Sleep duration,mean(SD)" = "sleep_duration",
  "Body mass index (kg/m²), mean(SD)" = "bmi",
  "Systolic blood pressure (mmHg), mean(SD)" = "systolic_bp",
  "Diastolic blood pressure (mmHg), mean(SD)" = "diastolic_bp",
  "Lung cancer, N(%)" = "lung_cancer",
  "Liver cancer, N(%)" = "liver_cancer",
  "Kidney cancer, N(%)" = "kidney_cancer",
  "Index of multiple deprivation (England), mean(SD)" = "ses_imd_england",
  "Index of multiple deprivation (Wales), mean(SD)" = "ses_imd_wales",
  "Index of multiple deprivation (Scotland), mean(SD)" = "ses_imd_scotland",
  "Cancer occurrences reported, mean(SD)" = "cancer_occurrences_reported",
  "Cancer histology, N(%)" = "cancer_histology",
  "Psychiatric care history admission, mean(SD)" = "mh_psychiatric_care_history_admission",
  "Work satisfaction, N(%)" = "mh_work_satisfaction",
  "C-reactive protein (mg/L), mean(SD)" = "biochem_crp",
  "Gamma glutamyltransferase, mean(SD)" = "gamma_glutamyltransferase",
  "DASH score, mean(SD)" = "DASH_score",
  "Hepatic steatosis index, mean(SD)" = "HSI",
  "Medication for cholesterol/BP/diabetes/hormones, N(%)" = "med_cholesterol_bp_diabetes_hormones",
  "Smoking exposure (pack-years), mean(SD)" = "pack_year_index",
  "Alcohol frequency of 6+ units, N(%)" = "alcohol_freq_6plus_units",
  "Alcohol consumption (units/week), mean(SD)" = "total_unit_alcohol_per_week",
  "Physical activity (MET-min/week), mean(SD)" = "MET_total",
  "CVH diet score, mean(SD)" = "CVH_diet_score",
  "CVH physical activity score, mean(SD)" = "CVH_pa_score",
  "CVH nicotine score, mean(SD)" = "CVH_nicotine_score",
  "CVH BMI score, mean(SD)" = "CVH_bmi_score",
  "CVH lipid score, mean(SD)" = "CVH_lipid_score",
  "CVH glucose score, mean(SD)" = "CVH_glucose_score",
  "CVH blood pressure score, mean(SD)" = "CVH_bp_score",
  "CVH total score, mean(SD)" = "CVH_score",
  "BHS metabolic, mean(SD)" = "BHS_metabolic",
  "BHS cardiovascular, mean(SD)" = "BHS_cardiovascular",
  "BHS immune, mean(SD)" = "BHS_immune",
  "BHS liver, mean(SD)" = "BHS_liver",
  "BHS kidney, mean(SD)" = "BHS_kidney",
  "BHS total, mean(SD)" = "BHS"
)

# drop columns not in the data
rename_map <- rename_map[rename_map %in% names(ukb)]

missing_cols <- setdiff(unname(rename_map), names(ukb))
if (length(missing_cols) > 0) {
  message("Skipped (not found): ", paste(missing_cols, collapse = ", "))
}

# prep dataset for full table 1
ukb2 <- ukb %>%
  mutate(
    sex = factor(sex),
    cvd = factor(cvd, levels = c(0, 1), labels = c("No CVD", "CVD"))
  ) %>%
  rename(!!!rename_map)

# renderers
my.render.cont <- function(x, ...) {
  sprintf("%.2f (%.2f)", mean(x, na.rm = TRUE), sd(x, na.rm = TRUE))
}

my.render.cat <- function(x, ...) {
  table1::render.categorical.default(x, ...)
}

render_p_value <- function(x, ...) {
  dat <- bind_rows(purrr::map(x, ~ data.frame(value = .)), .id = "group")
  dat <- dat[!is.na(dat$value), , drop = FALSE]
  if (nrow(dat) == 0) return("")
  if (is.numeric(dat$value)) {
    p <- tryCatch(t.test(value ~ group, data = dat)$p.value, error = function(e) NA_real_)
  } else {
    p <- tryCatch(suppressWarnings(chisq.test(table(dat$group, dat$value))$p.value), error = function(e) NA_real_)
  }
  if (is.na(p)) "" else scales::label_pvalue(accuracy = 0.001)(p)
}

# full table 1
vars_table1    <- setdiff(names(ukb2), c("cvd", "Participant ID", "Date of attending centre", "data type"))
table1_formula <- as.formula(paste("~", paste(sprintf("`%s`", vars_table1), collapse = " + "), "| cvd"))

table1_result <- table1(
  table1_formula,
  data               = ukb2,
  render.continuous  = my.render.cont,
  render.categorical = my.render.cat,
  render.missing     = NULL,
  extra.col          = list("P-value" = render_p_value),
  overall            = FALSE
)

# key variables table
ukb3 <- ukb %>%
  mutate(
    sex = factor(sex),
    cvd = factor(cvd, levels = c(0, 1), labels = c("No CVD", "CVD"))
  ) %>%
  rename(
    `Gender, n(%)`                               = sex,
    `CVD status`                                 = cvd,
    `Age at recruitment (years), mean(SD)`       = age_at_recruitment,
    `Body mass index (kg/m²), mean(SD)`          = bmi,
    `Systolic blood pressure (mmHg), mean(SD)`   = systolic_bp,
    `Diastolic blood pressure (mmHg), mean(SD)`  = diastolic_bp,
    `Alcohol consumption (units/week), mean(SD)` = total_unit_alcohol_per_week,
    `Physical activity (MET-min/week), mean(SD)` = MET_total,
    `Smoking exposure (pack-years), mean(SD)`    = pack_year_index,
    `CVH total score, mean(SD)`                  = CVH_score,
    `BHS total, mean(SD)`                        = BHS,
    `Apolipoprotein B, mean(SD)`                 = biochem_apob,
    `Total cholesterol (mmol/L), mean(SD)`       = biochem_cholesterol,
    `HbA1c (%), mean(SD)`                        = biochem_hba1c,
    `Triglycerides (mmol/L), mean(SD)`           = biochem_triglycerides,
    `Lung cancer, N(%)`                          = lung_cancer,
    `Liver cancer, N(%)`                         = liver_cancer,
    `Kidney cancer, N(%)`                        = kidney_cancer,
    `DASH score, mean(SD)`                       = DASH_score
  )

render_p_value2 <- function(x, ...) {
  dat <- dplyr::bind_rows(purrr::map(x, ~ data.frame(value = .)), .id = "group")
  dat <- dat[!is.na(dat$value), , drop = FALSE]
  if (is.numeric(dat$value)) {
    p <- tryCatch(t.test(value ~ group, data = dat)$p.value, error = function(e) NA)
  } else {
    p <- tryCatch(suppressWarnings(chisq.test(table(dat$group, dat$value))$p.value), error = function(e) NA)
  }
  if (is.na(p)) return("")
  scales::label_pvalue(accuracy = 0.001)(p)
}

table1_obj <- table1::table1(
  ~ `Gender, n(%)` +
    `Age at recruitment (years), mean(SD)` +
    `Body mass index (kg/m²), mean(SD)` +
    `Systolic blood pressure (mmHg), mean(SD)` +
    `Diastolic blood pressure (mmHg), mean(SD)` +
    `Alcohol consumption (units/week), mean(SD)` +
    `Physical activity (MET-min/week), mean(SD)` +
    `Smoking exposure (pack-years), mean(SD)` +
    `CVH total score, mean(SD)` +
    `BHS total, mean(SD)` +
    `Apolipoprotein B, mean(SD)` +
    `Total cholesterol (mmol/L), mean(SD)` +
    `HbA1c (%), mean(SD)` +
    `Triglycerides (mmol/L), mean(SD)` +
    `Lung cancer, N(%)` +
    `Liver cancer, N(%)` +
    `Kidney cancer, N(%)` +
    `DASH score, mean(SD)` | `CVD status`,
  data              = ukb3,
  render.continuous = my.render.cont,
  render.missing    = NULL,
  extra.col         = list(`P-value` = render_p_value2),
  overall           = FALSE
)

# save
sink(file.path(LOG_DIR, "session_info.txt"))
sessionInfo()
sink()

saveRDS(table1_result, file.path(TABLE_DIR, "table1_result.rds"))
saveRDS(table1_obj,    file.path(TABLE_DIR, "table1_result_key_variables.rds"))

all_files <- list.files("../outputs", recursive = TRUE, full.names = TRUE)
writeLines(all_files, file.path(TABLE_DIR, "saved_files_manifest.txt"))

cat("Total files:", length(all_files), "\n")