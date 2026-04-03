rm(list=ls())

if (sys.nframe() == 0 && !interactive()) {
  this_file <- normalizePath(sub("--file=", "", 
                                 commandArgs(trailingOnly = FALSE)[grep("--file=", commandArgs(trailingOnly = FALSE))][1]
  ))
  setwd(dirname(this_file))
}
if (interactive()) {
  setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
}

library(dplyr)
library(tibble)
library(stringr)


options(warn = 2)  # convierte warnings en errores para ver el traceback

# Load raw data
ukb <- readRDS("../outputs/ukb_raw.rds")

# Mapping rules: canonical name, domain, synthetic and real column bases
rules <- tribble(
  ~canonical,                 ~domain,              ~synth_base,                       ~real_base,
  
  "sex",                      "demographics",       "sex_31",                          "sex",
  "date_of_attending_centre", "demographics",       "date_of_attending_centre.0.0",    "date_of_attending_centre.0.0",
  "cvd_date",                 "output",             "cvd_date",                        "cvd_date",
  "cvd",                      "output",             "cvd",                             "cvd",
  "date_of_death",            "demographics",       "date_of_death.0.0",               "date_of_death.0.0",
  "age_at_recruitment",       "demographics",       "age_at_recruitment.0.0",          "age_at_recruitment.0.0",
  
  "bmi_1",                    "anthropometrics",    "anthro_bmi",                      "anthro_bmi",
  "bmi_2",                    "anthropometrics",    "anthro_bmi_second",               "anthro_bmi_second",
  "fat_free_mass",            "anthropometrics",    "anthro_fat_free_mass_whole_body",  "anthro_fat_free_mass_whole_body",
  "body_fat_pct",             "anthropometrics",    "anthro_body_fat_pct",             "anthro_body_fat_pct",
  "bmr",                      "anthropometrics",    "anthro_bmr",                      "anthro_bmr",
  
  "sbp_manual",               "blood_pressure",     "bp_systolic_manual",              "bp_systolic_manual",
  "dbp_manual",               "blood_pressure",     "bp_diastolic_manual",             "bp_diastolic_manual",
  "sbp_auto",                 "blood_pressure",     "bp_systolic_auto",                "bp_systolic_auto",
  "dbp_auto",                 "blood_pressure",     "bp_diastolic_auto",               "bp_diastolic_auto",
  
  "ecg_heart_rate",           "ecg",                "ecg_heart_rate",                  "ecg_heart_rate",
  "ecg_load",                 "ecg",                "ecg_load",                        "ecg_load",
  "fitness_bicycle_speed",    "ecg",                "fitness_bicycle_speed",           "fitness_bicycle_speed",
  "ecg_phase_time",           "ecg",                "ecg_phase_time",                  "ecg_phase_time",
  
  "cardiac_pulse_rate",       "pwa",                "cardiac_pulse_rate",              "cardiac_pulse_rate",
  "pwa_reflection_index",     "pwa",                "pwa_reflection_index",            "pwa_reflection_index",
  "pwa_peak_to_peak_time",    "pwa",                "pwa_peak_to_peak_time",           "pwa_peak_to_peak_time",
  "pwa_peak_position",        "pwa",                "pwa_peak_position",               "pwa_peak_position",
  "pwa_notch_position",       "pwa",                "pwa_notch_position",              "pwa_notch_position",
  
  "energy",                   "diet",               "diet24_energy",                   "diet24_energy",
  "dietary_fibre",            "diet",               "diet24_dietary_fibre",            "diet24_dietary_fibre",
  "sugars",                   "diet",               "diet24_sugars",                   "diet24_sugars",
  "saturated_fat",            "diet",               "diet24_saturated_fat",            "diet24_saturated_fat",
  "polyunsaturated_fat",      "diet",               "diet24_polyunsaturated_fat",      "diet24_polyunsaturated_fat",
  "beef_intake",              "diet",               "beef_intake",                     "beef_intake",
  "diet_carbohydrate",        "diet",               "diet24_carbohydrate",             "diet24_carbohydrate",
  
  "diet24_veg_mixed_intake",         "diet",        "diet24_veg_mixed_intake",         "diet24_veg_mixed_intake",
  "diet24_veg_pieces_intake",        "diet",        "diet24_veg_pieces_intake",        "diet24_veg_pieces_intake",
  "diet24_veg_other_intake",         "diet",        "diet24_veg_other_intake",         "diet24_veg_other_intake",
  "diet_veg_cooked_intake",          "diet",        "diet_veg_cooked_intake",          "diet_veg_cooked_intake",
  "diet_veg_salad_raw_intake",       "diet",        "diet_veg_salad_raw_intake",       "diet_veg_salad_raw_intake",
  "diet_veg_consumers",              "diet",        "diet_veg_consumers",              "diet_veg_consumers",
  
  "diet_fruit_fresh_intake",         "diet",        "diet_fruit_fresh_intake",         "diet_fruit_fresh_intake",
  "diet_fruit_dried_intake",         "diet",        "diet_fruit_dried_intake",         "diet_fruit_dried_intake",
  "diet_fruit_consumers",            "diet",        "diet_fruit_consumers",            "diet_fruit_consumers",
  "diet24_fruit_dried_intake",       "diet",        "diet24_fruit_dried_intake",       "diet24_fruit_dried_intake",
  "diet24_fruit_mixed_intake",       "diet",        "diet24_fruit_mixed_intake",       "diet24_fruit_mixed_intake",
  
  "resp_fev1_best",              "pulmonary_function", "resp_fev1_best",              "resp_fev1_best",
  "resp_fvc_best",               "pulmonary_function", "resp_fvc_best",               "resp_fvc_best",
  "resp_fev1_z_score",           "pulmonary_function", "resp_fev1_z_score",           "resp_fev1_z_score",
  "resp_fvc_z_score",            "pulmonary_function", "resp_fvc_z_score",            "resp_fvc_z_score",
  "resp_fev1_fvc_ratio_z_score", "pulmonary_function", "resp_fev1_fvc_ratio_z_score", "resp_fev1_fvc_ratio_z_score",
  
  "alcohol_intake_freq",       "diet",              "alcohol_intake_freq",             "alcohol_intake_freq",
  "alcohol_intake_typical_day","diet",              "alcohol_intake_typical_day",      "alcohol_intake_typical_day",
  "alcohol_freq_6plus_units",  "diet",              "alcohol_freq_6plus_units",        "alcohol_freq_6plus_units",
  
  "ecg_during_exercise_duration", "ecg_function",  "ecg_during_exercise_duration",    "ecg_during_exercise_duration",
  "fitness_workload_max",      "ecg_function",      "fitness_workload_max",            "fitness_workload_max",
  "fitness_heart_rate_max",    "ecg_function",      "fitness_heart_rate_max",          "fitness_heart_rate_max",
  
  "smoking_age_started_former",            "smoking", "smoking_age_started_former",        "smoking_age_started_former",
  "smoking_cigarettes_daily_previous",     "smoking", "smoking_cigarettes_daily_previous", "smoking_cigarettes_daily_previous",
  "smoking_age_stopped",                   "smoking", "smoking_age_stopped",               "smoking_age_stopped",
  "smoking_cigarettes_daily_current",      "smoking", "smoking_cigarettes_daily_current",  "smoking_cigarettes_daily_current",
  "smoking_time_to_first_cigarette",       "smoking", "smoking_time_to_first_cigarette",   "smoking_time_to_first_cigarette",
  "smoking_status",                        "smoking", "smoking_status",                    "smoking_status",
  
  "number_of_daysweek_walked_10_minutes",             "sedentary_behaviour", "number_of_daysweek_walked_10_minutes_864",             "number_of_daysweek_walked_10_minutes",
  "duration_of_walks",                                "sedentary_behaviour", "duration_of_walks_874",                                "duration_of_walks",
  "number_of_daysweek_of_moderate_physical_activity", "sedentary_behaviour", "number_of_daysweek_of_moderate_physical_activity_884", "number_of_daysweek_of_moderate_physical_activity",
  "duration_of_moderate_activity",                    "sedentary_behaviour", "duration_of_moderate_activity_894",                    "duration_of_moderate_activity",
  "number_of_daysweek_of_vigorous_physical_activity", "sedentary_behaviour", "number_of_daysweek_of_vigorous_physical_activity_904", "number_of_daysweek_of_vigorous_physical_activity",
  "duration_of_vigorous_activity",                    "sedentary_behaviour", "duration_of_vigorous_activity_914",                    "duration_of_vigorous_activity",
  "activity_heavy_diy_freq_4wk",                      "sedentary_behaviour", "activity_heavy_diy_freq_4wk",                         "activity_heavy_diy_freq_4wk",
  "activity_heavy_diy_duration",                      "sedentary_behaviour", "activity_heavy_diy_duration",                         "activity_heavy_diy_duration",
  "activity_other_exercise_freq_4wk",                 "sedentary_behaviour", "activity_other_exercise_freq_4wk",                    "activity_other_exercise_freq_4wk",
  "activity_other_exercise_duration",                 "sedentary_behaviour", "activity_other_exercise_duration",                    "activity_other_exercise_duration",
  
  "igf1",                                  "lab", "igf1",                                  "igf1",
  "gamma_glutamyltransferase",             "lab", "gamma_glutamyltransferase",              "gamma_glutamyltransferase",
  "creatinine",                            "lab", "creatinine",                             "creatinine",
  "aspartate_aminotransferase",            "lab", "aspartate_aminotransferase",             "aspartate_aminotransferase",
  "alanine_aminotransferase",              "lab", "alanine_aminotransferase",               "alanine_aminotransferase",
  "blood_wbc_count",                       "lab", "blood_wbc_count",                        "blood_wbc_count",
  "blood_rbc_count",                       "lab", "blood_rbc_count",                        "blood_rbc_count",
  "blood_hemoglobin_conc",                 "lab", "blood_hemoglobin_conc",                  "blood_hemoglobin_conc",
  "blood_hematocrit_pct",                  "lab", "blood_hematocrit_pct",                   "blood_hematocrit_pct",
  "blood_platelet_count",                  "lab", "blood_platelet_count",                   "blood_platelet_count",
  "blood_platelet_volume_mean",            "lab", "blood_platelet_volume_mean",             "blood_platelet_volume_mean",
  "blood_platelet_distribution_width",     "lab", "blood_platelet_distribution_width",      "blood_platelet_distribution_width",
  "blood_reticulocyte_pct",                "lab", "blood_reticulocyte_pct",                 "blood_reticulocyte_pct",
  "blood_reticulocyte_count",              "lab", "blood_reticulocyte_count",               "blood_reticulocyte_count",
  "blood_reticulocyte_volume_mean",        "lab", "blood_reticulocyte_volume_mean",         "blood_reticulocyte_volume_mean",
  "blood_reticulocyte_immature_fraction",  "lab", "blood_reticulocyte_immature_fraction",   "blood_reticulocyte_immature_fraction",
  "blood_reticulocyte_hls_pct",            "lab", "blood_reticulocyte_hls_pct",             "blood_reticulocyte_hls_pct",
  "blood_reticulocyte_hls_count",          "lab", "blood_reticulocyte_hls_count",           "blood_reticulocyte_hls_count",
  "biochem_apoa",                          "lab", "biochem_apoa",                           "biochem_apoa",
  "biochem_apob",                          "lab", "biochem_apob",                           "biochem_apob",
  "biochem_cholesterol",                   "lab", "biochem_cholesterol",                    "biochem_cholesterol",
  "biochem_crp",                           "lab", "biochem_crp",                            "biochem_crp",
  "biochem_glucose",                       "lab", "biochem_glucose",                        "biochemm_glucose",
  "biochem_hba1c",                         "lab", "biochem_hba1c",                          "biochem_hba1c",
  "biochem_hdl",                           "lab", "biochem_hdl",                            "biochem_hdl",
  "biochem_ldl_direct",                    "lab", "biochem_ldl_direct",                     "biochem_ldl_direct",
  "biochem_lipoa",                         "lab", "biochem_lipoa",                          "biochem_lipoa",
  "biochem_triglycerides",                 "lab", "biochem_triglycerides",                  "biochemm_triglycerides",
  "biochem_sodium_urine",                  "lab", "biochem_sodium_urine",                   "biochem_sodium_urine",
  
  "social_leisure_activities_1", "social_support", "social_leisure_activities.0.0", "social_leisure_activities",
  "social_leisure_activities_2", "social_support", "social_leisure_activities.0.1", "social_leisure_activities",
  "social_leisure_activities_3", "social_support", "social_leisure_activities.0.2", "social_leisure_activities",
  "social_leisure_activities_4", "social_support", "social_leisure_activities.0.3", "social_leisure_activities",
  "social_leisure_activities_5", "social_support", "social_leisure_activities.0.4", "social_leisure_activities",
  
  "social_friend_family_visit_freq",  "social_support",           "social_friend_family_visit_freq.0.0",      "social_friend_family_visit_freq",
  
  "social_private_healthcare",  "sociodemographic_factors", "social_private_healthcare.0.0",   "social_private_healthcare",
  "ses_employment_status",      "sociodemographic_factors", "ses_employment_status.0.0",        "ses_employment_status",
  "ses_imd_england",            "sociodemographic_factors", "ses_imd_england.0.0",              "ses_imd_england",
  "ses_imd_wales",              "sociodemographic_factors", "ses_imd_wales.0.0",                "ses_imd_wales",
  "ses_imd_scotland",           "sociodemographic_factors", "ses_imd_scotland.0.0",             "ses_imd_scotland",
  
  "mh_mood_swings",             "mental_health", "mh_mood_swings.0.0",             "mh_mood_swings",
  "mh_miserableness",           "mental_health", "mh_miserableness.0.0",           "mh_miserableness",
  "mh_irritability",            "mental_health", "mh_irritability.0.0",            "mh_irritability",
  "mh_sensitivity_hurt",        "mental_health", "mh_sensitivity_hurt.0.0",        "mh_sensitivity_hurt",
  "mh_fed_up",                  "mental_health", "mh_fed_up.0.0",                  "mh_fed_up",
  "mh_nervous",                 "mental_health", "mh_nervous.0.0",                 "mh_nervous",
  "mh_worrier_anxious",         "mental_health", "mh_worrier_anxious.0.0",         "mh_worrier_anxious",
  "mh_tense_highly_strung",     "mental_health", "mh_tense_highly_strung.0.0",     "mh_tense_highly_strung",
  "mh_worry_after_embarrass",   "mental_health", "mh_worry_after_embarrass.0.0",   "mh_worry_after_embarrass",
  "mh_suffer_nerves",           "mental_health", "mh_suffer_nerves.0.0",           "mh_suffer_nerves",
  "mh_loneliness",              "mental_health", "mh_loneliness.0.0",              "mh_loneliness",
  "mh_guilt",                   "mental_health", "mh_guilt.0.0",                   "mh_guilt",
  
  "mh_seen_gp_nerves",          "mental_health", "mh_seen_gp_nerves.0.0",          "mh_seen_gp_nerves",
  "mh_seen_psychiatrist",       "mental_health", "mh_seen_psychiatrist.0.0",       "mh_seen_psychiatrist",
  
  "mh_anxiety_worst_muscles_tense",           "mental_health", "mh_anxiety_worst_muscles_tense.0.0",           "mh_anxiety_worst_muscles_tense",
  "mh_anxiety_worst_difficulty_concentrate",  "mental_health", "mh_anxiety_worst_difficulty_concentrate.0.0",  "mh_anxiety_worst_difficulty_concentrate",
  "mh_anxiety_ever_worried_month",            "mental_health", "mh_anxiety_ever_worried_month.0.0",            "mh_anxiety_ever_worried_month",
  "mh_anxiety_worst_more_irritable",          "mental_health", "mh_anxiety_worst_more_irritable.0.0",          "mh_anxiety_worst_more_irritable",
  "mh_anxiety_worst_keyed_up",                "mental_health", "mh_anxiety_worst_keyed_up.0.0",                "mh_anxiety_worst_keyed_up",
  "mh_anxiety_worried_more_than_others",      "mental_health", "mh_anxiety_worried_more_than_others.0.0",      "mh_anxiety_worried_more_than_others",
  "mh_anxiety_worst_restless",                "mental_health", "mh_anxiety_worst_restless.0.0",                "mh_anxiety_worst_restless",
  "mh_anxiety_worst_sleep_trouble",           "mental_health", "mh_anxiety_worst_sleep_trouble.0.0",           "mh_anxiety_worst_sleep_trouble",
  "mh_anxiety_professional_informed",         "mental_health", "mh_anxiety_professional_informed.0.0",         "mh_anxiety_professional_informed",
  "mh_anxiety_worst_easily_tired",            "mental_health", "mh_anxiety_worst_easily_tired.0.0",            "mh_anxiety_worst_easily_tired",
  "mh_anxiety_worst_impact_roles",            "mental_health", "mh_anxiety_worst_impact_roles.0.0",            "mh_anxiety_worst_impact_roles",
  
  "mh_depression_longest_period",          "mental_health", "mh_depression_longest_period.0.0",          "mh_depression_longest_period",
  "mh_depression_num_episodes",            "mental_health", "mh_depression_num_episodes.0.0",            "mh_depression_num_episodes",
  "mh_depression_age_first",               "mental_health", "mh_depression_age_first.0.0",               "mh_depression_age_first",
  "mh_depression_age_last",                "mental_health", "mh_depression_age_last.0.0",                "mh_depression_age_last",
  "mh_depression_single_episode_probable", "mental_health", "mh_depression_single_episode_probable.0.0", "mh_depression_single_episode_probable",
  "mh_depression_recurrent_moderate",      "mental_health", "mh_depression_recurrent_moderate.0.0",      "mh_depression_recurrent_moderate",
  "mh_depression_recurrent_severe",        "mental_health", "mh_depression_recurrent_severe.0.0",        "mh_depression_recurrent_severe",
  "mh_depression_stressful_event",         "mental_health", "mh_depression_stressful_event.0.0",         "mh_depression_stressful_event",
  
  "mh_bipolar_major_depression_status", "mental_health", "mh_bipolar_major_depression_status.0.0", "mh_bipolar_major_depression_status",
  
  "sleep_trouble_falling",   "mental_health", "sleep_trouble_falling.0.0",   "sleep_trouble_falling",
  "sleep_sleeping_too_much", "mental_health", "sleep_sleeping_too_much.0.0", "sleep_sleeping_too_much",
  "sleep_waking_early",      "mental_health", "sleep_waking_early.0.0",      "sleep_waking_early",
  
  "mh_addiction_substance_behaviour", "addiction", "mh_addiction_substance_behaviour.0.0", "mh_addiction_substance_behaviour",
  
  "dx_diabetes_gestational_only",         "comorbidities", "dx_diabetes_gestational_only.0.0",         "dx_diabetes_gestational_only",
  "dx_cancer",                            "comorbidities", "dx_cancer.0.0",                            "dx_cancer",
  "med_cholesterol_bp_diabetes_hormones", "comorbidities", "med_cholesterol_bp_diabetes_hormones.0.0", "med_cholesterol_bp_diabetes_hormones",
  
  "mental_categories_1", "comorbidities", "mental_categories.0.0", "mental_categories",
  "mental_categories_2", "comorbidities", "mental_categories.0.1", "mental_categories",
  
  "cancer_occurrences_reported",           "comorbidities", "cancer_occurrences_reported.0.0",           "cancer_occurrences_reported",
  "cancer_histology",                      "comorbidities", "cancer_histology.0.0",                      "cancer_histology",
  "cancer_behaviour",                      "comorbidities", "cancer_behaviour.0.0",                      "cancer_behaviour",
  "mh_psychiatric_care_history_admission", "comorbidities", "mh_psychiatric_care_history_admission.0.0", "mh_psychiatric_care_history_admission",
  
  "occ_chemical_fumes",        "pollutants", "occ_chemical_fumes.0.0",        "occ_chemical_fumes",
  "occ_cigarette_smoke",       "pollutants", "occ_cigarette_smoke.0.0",       "occ_cigarette_smoke",
  "occ_paints_thinners_glues", "pollutants", "occ_paints_thinners_glues.0.0", "occ_paints_thinners_glues",
  "occ_pesticides",            "pollutants", "occ_pesticides.0.0",            "occ_pesticides",
  "occ_diesel_exhaust",        "pollutants", "occ_diesel_exhaust.0.0",        "occ_diesel_exhaust",
  "occ_breathing_problems",    "pollutants", "occ_breathing_problems.0.0",    "occ_breathing_problems",
  
  "mh_work_satisfaction",        "mental_health", "mh_work_satisfaction",        "mh_work_satisfaction",
  "mh_health_satisfaction",      "mental_health", "mh_health_satisfaction",      "mh_health_satisfaction",
  "mh_family_satisfaction",      "mental_health", "mh_family_satisfaction",      "mh_family_satisfaction",
  "mh_friendships_satisfaction", "mental_health", "mh_friendships_satisfaction", "mh_friendships_satisfaction",
  "mh_financial_satisfaction",   "mental_health", "mh_financial_satisfaction",   "mh_financial_satisfaction",
  
  "cancer_code", "health", "cancer_code", "cancer_code", 
  "sleep_duration", "sleep", "sleep_duration.0.0", "sleep_duration.0.0"
)


# Match columns by base name, allowing .N or .N.N suffixes
find_like_cols <- function(df, base) {
  if (is.na(base) || !nzchar(base)) return(character(0))
  grep(paste0("^", base, "(\\.[0-9]+\\.[0-9]+|\\.[0-9]+)?$"), names(df), value = TRUE)
}

find_cols_for_rule <- function(df, synth_base, real_base) {
  cols_s <- find_like_cols(df, synth_base)
  if (length(cols_s) > 0) return(cols_s)
  find_like_cols(df, real_base)
}

find_col <- function(data, stem, required = TRUE) {
  nms <- names(data)
  if (stem %in% nms) return(stem)
  hits <- grep(paste0("^", gsub("\\.", "\\\\.", stem), "(\\.[0-9]+\\.[0-9]+)?$"), nms, value = TRUE)
  if (length(hits) == 0)
    hits <- grep(paste0("^", gsub("\\.", "\\\\.", stem), "\\."), nms, value = TRUE)
  if (length(hits) == 0) {
    if (required) stop(paste("Column not found for:", stem))
    return(NA_character_)
  }
  hits[1]
}

find_cols <- function(data, stem) {
  nms <- names(data)
  grep(paste0("^", gsub("\\.", "\\\\.", stem), "\\.[0-9]+\\.[0-9]+$"), nms, value = TRUE)
}

pull_col <- function(data, stem, required = TRUE) {
  col <- find_col(data, stem, required = required)
  if (is.na(col)) return(rep(NA, nrow(data)))
  data[[col]]
}

# Keep only columns needed by the rules
cols_needed <- unique(unlist(lapply(seq_len(nrow(rules)), function(i) {
  c(find_like_cols(ukb, rules$synth_base[i]),
    find_like_cols(ukb, rules$real_base[i]))
})))

ukb_small <- ukb %>% dplyr::select(dplyr::any_of(cols_needed))

# Add pain_medication columns (not in rules)
pain_cols_raw <- grep("^pain_medication\\.", names(ukb), value = TRUE)
if (length(pain_cols_raw) > 0) {
  ukb_small <- bind_cols(ukb_small, ukb[, pain_cols_raw, drop = FALSE])
}

# Build canonical features
# Prefer not to answer / Prefer not to say -> -1
# Do not know / Not applicable / Not known  -> NA
make_mean_features <- function(df, rules_tbl) {
  for (i in seq_len(nrow(rules_tbl))) {
    canon <- rules_tbl$canonical[i]
    sb    <- rules_tbl$synth_base[i]
    rb    <- rules_tbl$real_base[i]
    cols  <- find_cols_for_rule(df, sb, rb)
    if (length(cols) == 0) { df[[canon]] <- NA; next }
    if (length(cols) == 1) { df[[canon]] <- df[[cols[1]]]; next }
    first_col      <- df[[cols[1]]]
    is_categorical <- is.factor(first_col) || is.character(first_col) ||
      inherits(first_col, "Date") || inherits(first_col, "POSIXct") || is.logical(first_col)
    if (is_categorical) {
      X <- df[, cols, drop = FALSE]
      df[[canon]] <- apply(X, 1, function(row) {
        non_na <- row[!is.na(row)]
        if (length(non_na) == 0) NA else non_na[1]
      })
    } else {
      X <- df[, cols, drop = FALSE]
      # Recode before converting to numeric
      X <- as.data.frame(lapply(X, function(z) {
        z <- trimws(as.character(z))
        z[z %in% c("Prefer not to answer", "Prefer not to say")] <- "-1"
        z[z %in% c("Do not know", "Not applicable", "Not known")] <- NA
        z
      }))
      X_num <- as.data.frame(lapply(X, function(z) suppressWarnings(as.numeric(z))))
      # If any instance is -1, mark the whole row as -1; otherwise take the mean
      has_pna <- apply(X_num, 1, function(row) any(row == -1, na.rm = TRUE))
      means   <- rowMeans(as.matrix(X_num), na.rm = TRUE)
      df[[canon]] <- ifelse(has_pna, -1, means)
    }
  }
  df
}

ukb_feat  <- make_mean_features(ukb_small, rules)
ukb_final <- ukb_feat %>% dplyr::select(dplyr::any_of(rules$canonical))

# Derived variables: average repeated measures
make_mean_var <- function(df, cols, new_name) {
  if (all(cols %in% names(df))) {
    df[[new_name]] <- rowMeans(df[, cols], na.rm = TRUE)
    df <- df %>% dplyr::select(-dplyr::all_of(cols))
  }
  df
}

ukb_final <- make_mean_var(ukb_final, c("bmi_1", "bmi_2"), "bmi")
ukb_final <- make_mean_var(ukb_final, c("sbp_manual", "sbp_auto"), "systolic_bp")
ukb_final <- make_mean_var(ukb_final, c("dbp_manual", "dbp_auto"), "diastolic_bp")

# QC: set values outside plausible range to NA
qc_range <- function(x, lo, hi) ifelse(x < lo | x > hi, NA_real_, x)

ukb_final$bmi             <- qc_range(ukb_final$bmi,             12,    75)
ukb_final$fat_free_mass   <- qc_range(ukb_final$fat_free_mass,   18.7,  100)
ukb_final$bmr             <- qc_range(ukb_final$bmr,             3364,  15506)
ukb_final$body_fat_pct    <- qc_range(ukb_final$body_fat_pct,    5,     70)
ukb_final$systolic_bp     <- qc_range(ukb_final$systolic_bp,     0,     255)
ukb_final$diastolic_bp    <- qc_range(ukb_final$diastolic_bp,    0,     255)
ukb_final$ecg_heart_rate  <- qc_range(ukb_final$ecg_heart_rate,  30,    300)
ukb_final$ecg_load        <- qc_range(ukb_final$ecg_load,        0,     270)
ukb_final$pwa_reflection_index  <- qc_range(ukb_final$pwa_reflection_index,  -4813, 1248)
ukb_final$pwa_peak_to_peak_time <- qc_range(ukb_final$pwa_peak_to_peak_time, 1,     1614)
ukb_final$pwa_peak_position     <- qc_range(ukb_final$pwa_peak_position,     3,     67)
ukb_final$pwa_notch_position    <- qc_range(ukb_final$pwa_notch_position,    17,    94)

# Cancer flags from free-text cancer_code columns
cancer_cols <- grep("^cancer_code", names(ukb_small), value = TRUE)

ukb_final$lung_cancer <- apply(ukb_small[, cancer_cols, drop = FALSE], 1, function(row)
  sum(row %in% c("lung cancer","non-small cell lung cancer","small cell lung cancer"), na.rm = TRUE))

ukb_final$liver_cancer <- apply(ukb_small[, cancer_cols, drop = FALSE], 1, function(row)
  sum(row == "liver/hepatocellular cancer", na.rm = TRUE))

ukb_final$kidney_cancer <- apply(ukb_small[, cancer_cols, drop = FALSE], 1, function(row)
  sum(row == "kidney/renal cell cancer", na.rm = TRUE))

ukb_final <- ukb_final %>% dplyr::select(-dplyr::any_of("cancer_code"))

# Diet scores: quintile scoring (1-5) per nutrient
lab_diet_ranges <- tribble(
  ~canonical,            ~min,  ~max,
  "diet_carbohydrate",   0,     2562.05,
  "energy",              0,     78205.7,
  "dietary_fibre",       0,     153.88,
  "sugars",              0,     1342.33,
  "saturated_fat",       0,     252.17,
  "polyunsaturated_fat", 0,     150.71
)

clean_apply_range <- function(x, low, high) {
  x <- suppressWarnings(as.numeric(as.character(x)))
  x[!is.na(x) & (x < low | x > high)] <- NA_real_
  x
}

quintile_score_1_5 <- function(x, healthy_high = TRUE) {
  score <- rep(NA_real_, length(x))
  valid <- !is.na(x)
  if (sum(valid) == 0) return(score)
  xv <- x[valid]
  if (length(unique(xv)) < 2) { score[valid] <- 3; return(score) }
  qs <- unique(quantile(xv, probs = seq(0,1,0.2), na.rm = TRUE))
  if (length(qs) < 6) {
    r   <- rank(xv, ties.method = "average")
    grp <- cut(r, breaks = quantile(r, probs = seq(0,1,0.2), na.rm=TRUE), include.lowest=TRUE, labels=FALSE)
  } else {
    grp <- cut(xv, breaks = qs, include.lowest=TRUE, labels=FALSE)
  }
  score_map    <- if (healthy_high) c(1,2,3,4,5) else c(5,4,3,2,1)
  score[valid] <- score_map[grp]
  score
}

healthy_direction <- tribble(
  ~canonical,            ~healthy_high,
  "diet_carbohydrate",   FALSE,
  "dietary_fibre",       TRUE,
  "sugars",              FALSE,
  "saturated_fat",       FALSE,
  "polyunsaturated_fat", TRUE
)

for (i in seq_len(nrow(lab_diet_ranges))) {
  v    <- lab_diet_ranges$canonical[i]
  low  <- lab_diet_ranges$min[i]
  high <- lab_diet_ranges$max[i]
  if (!v %in% names(ukb_final) || v == "energy") next
  dir_flag <- healthy_direction$healthy_high[match(v, healthy_direction$canonical)]
  if (length(dir_flag) == 0 || is.na(dir_flag)) next
  x_clean <- clean_apply_range(ukb_final[[v]], low, high)
  ukb_final[[paste0(v, "_score")]] <- quintile_score_1_5(x_clean, healthy_high = dir_flag)
}

# Veg & fruit scores
is_do_not_know <- function(x) grepl("^Do not know$",   trimws(as.character(x)), ignore.case = TRUE)
is_prefer_not  <- function(x) grepl("^Prefer not to$", trimws(as.character(x)), ignore.case = TRUE)

average_with_prefer_not <- function(...) {
  mat <- cbind(...)
  apply(mat, 1, function(row) {
    if (any(row == -1, na.rm = TRUE)) return(-1)
    else if (any(is.na(row)))         return(NA_real_)
    else                              return(mean(row))
  })
}

quintile_score_1_5_vf <- function(x) {
  x     <- suppressWarnings(as.numeric(as.character(x)))
  score <- rep(NA_real_, length(x))
  valid <- !is.na(x) & x != -1
  if (sum(valid) > 0) {
    r    <- rank(x[valid], ties.method = "average")
    brks <- unique(quantile(r, probs = seq(0,1,0.2), na.rm = TRUE))
    score[valid] <- if (length(brks) < 2) 3 else
      cut(r, breaks = brks, include.lowest = TRUE, labels = FALSE)
  }
  score[!is.na(x) & x == -1] <- -1
  score
}

recode_veg_diet24_portion <- function(x) {
  x <- trimws(as.character(x))
  dplyr::case_when(
    x %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
    is_do_not_know(x) ~ NA_real_,
    x == "quarter"   ~ 0.25, x == "half"        ~ 0.5,
    x == "1"         ~ 1,    x == "2"            ~ 2,
    x == "3+"        ~ 3,    TRUE                ~ NA_real_
  )
}

recode_veg_general_intake <- function(x) {
  x <- trimws(as.character(x))
  result <- rep(NA_real_, length(x))
  result[x %in% c("Prefer not to answer", "Prefer not to say")] <- -1
  result[is_do_not_know(x)] <- NA_real_
  result[x == "Less than one"] <- 0.5
  numeric_mask <- grepl("^[0-9]+$", x)
  result[numeric_mask] <- suppressWarnings(as.numeric(x[numeric_mask]))
  result
}

recode_status_only <- function(x) {
  x <- trimws(as.character(x))
  dplyr::case_when(
    x %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
    is_do_not_know(x) ~ NA_real_,
    TRUE ~ 0
  )
}

recode_fruit_general_intake <- function(x) {
  x <- trimws(as.character(x))
  x[x == "-999909999"] <- NA
  result <- rep(NA_real_, length(x))
  result[x %in% c("Prefer not to answer", "Prefer not to say")] <- -1
  result[is_do_not_know(x)] <- NA_real_
  result[x == "Less than one"] <- 0.5
  numeric_mask <- grepl("^[0-9]+$", x)
  result[numeric_mask] <- suppressWarnings(as.numeric(x[numeric_mask]))
  result
}

recode_fruit_diet24_portion <- function(x) {
  x <- trimws(as.character(x))
  dplyr::case_when(
    x %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
    is_do_not_know(x) ~ NA_real_,
    x == "half"      ~ 0.5, x == "1"           ~ 1,
    x == "2"         ~ 2,   x == "3"            ~ 3,
    x == "4+"        ~ 4,   TRUE                ~ NA_real_
  )
}

get_first_match <- function(df, base) {
  cols <- find_like_cols(df, base)
  if (length(cols) == 0) return(NULL)
  df[[cols[1]]]
}

veg_mixed_rec  <- { v <- get_first_match(ukb_small, "diet24_veg_mixed_intake");   if (!is.null(v)) recode_veg_diet24_portion(v)  else rep(NA_real_, nrow(ukb_small)) }
veg_pieces_rec <- { v <- get_first_match(ukb_small, "diet24_veg_pieces_intake");  if (!is.null(v)) recode_veg_diet24_portion(v)  else rep(NA_real_, nrow(ukb_small)) }
veg_other_rec  <- { v <- get_first_match(ukb_small, "diet24_veg_other_intake");   if (!is.null(v)) recode_veg_diet24_portion(v)  else rep(NA_real_, nrow(ukb_small)) }
veg_cooked_rec <- { v <- get_first_match(ukb_small, "diet_veg_cooked_intake");    if (!is.null(v)) recode_veg_general_intake(v)  else rep(NA_real_, nrow(ukb_small)) }
veg_salad_rec  <- { v <- get_first_match(ukb_small, "diet_veg_salad_raw_intake"); if (!is.null(v)) recode_veg_general_intake(v)  else rep(NA_real_, nrow(ukb_small)) }
veg_status_rec <- { v <- get_first_match(ukb_small, "diet_veg_consumers");        if (!is.null(v)) recode_status_only(v)          else rep(NA_real_, nrow(ukb_small)) }

fruit_fresh_rec   <- { v <- get_first_match(ukb_small, "diet_fruit_fresh_intake");   if (!is.null(v)) recode_fruit_general_intake(v)  else rep(NA_real_, nrow(ukb_small)) }
fruit_dried_rec   <- { v <- get_first_match(ukb_small, "diet_fruit_dried_intake");   if (!is.null(v)) recode_fruit_general_intake(v)  else rep(NA_real_, nrow(ukb_small)) }
fruit_status_rec  <- { v <- get_first_match(ukb_small, "diet_fruit_consumers");      if (!is.null(v)) recode_status_only(v)             else rep(NA_real_, nrow(ukb_small)) }
fruit24_dried_rec <- { v <- get_first_match(ukb_small, "diet24_fruit_dried_intake"); if (!is.null(v)) recode_fruit_diet24_portion(v)   else rep(NA_real_, nrow(ukb_small)) }
fruit24_mixed_rec <- { v <- get_first_match(ukb_small, "diet24_fruit_mixed_intake"); if (!is.null(v)) recode_fruit_diet24_portion(v)   else rep(NA_real_, nrow(ukb_small)) }

veg_average_raw <- average_with_prefer_not(veg_mixed_rec, veg_pieces_rec, veg_other_rec, veg_cooked_rec, veg_salad_rec)
veg_average     <- ifelse(veg_status_rec == -1, -1, ifelse(is.na(veg_status_rec), NA_real_, veg_average_raw))

fruit_average_raw <- average_with_prefer_not(fruit_fresh_rec, fruit_dried_rec, fruit24_dried_rec, fruit24_mixed_rec)
fruit_average     <- ifelse(fruit_status_rec == -1, -1, ifelse(is.na(fruit_status_rec), NA_real_, fruit_average_raw))

ukb_final$veg_quintile_score   <- quintile_score_1_5_vf(veg_average)
ukb_final$fruit_quintile_score <- quintile_score_1_5_vf(fruit_average)

# Pulmonary QC
lung_ranges <- tribble(
  ~canonical,                        ~min,    ~max,
  "resp_fev1_best",                  0.09,   14.65,
  "resp_fvc_best",                   0.30,   17.24,
  "resp_fev1_z_score",              -4.986,   4.999,
  "resp_fvc_z_score",               -4.999,   4.997,
  "resp_fev1_fvc_ratio_z_score",    -4.21,    5.44
)

for (i in seq_len(nrow(lung_ranges))) {
  v <- lung_ranges$canonical[i]
  if (!v %in% names(ukb_final)) next
  ukb_final[[v]] <- qc_range(suppressWarnings(as.numeric(ukb_final[[v]])),
                             lung_ranges$min[i], lung_ranges$max[i])
}

# ECG functional QC
if ("fitness_workload_max"   %in% names(ukb_final)) ukb_final$fitness_workload_max   <- qc_range(ukb_final$fitness_workload_max,   0,   140)
if ("fitness_heart_rate_max" %in% names(ukb_final)) ukb_final$fitness_heart_rate_max <- qc_range(ukb_final$fitness_heart_rate_max, 120, 220)

# Alcohol
recode_alcohol_intake_freq <- function(x) {
  x <- as.character(x)
  x[x %in% c("Do not know")] <- NA
  x[x %in% c("Prefer not to answer", "Prefer not to say")] <- "-1"
  dplyr::case_when(
    x == "Daily or almost daily"      ~ 7,   x == "Three or four times a week" ~ 3.5,
    x == "Once or twice a week"       ~ 1.5, x == "One to three times a month" ~ 0.5,
    x == "Special occasions only"     ~ 0.1, x == "Never"                      ~ 0,
    x == "-1"                         ~ -1,  TRUE ~ NA_real_
  )
}

recode_alcohol_typical_day <- function(x) {
  x <- as.character(x)
  x[x %in% c("Do not know")] <- NA
  x[x %in% c("Prefer not to answer", "Prefer not to say")] <- "-1"
  dplyr::case_when(
    x == "1 or 2" ~ 1.5, x == "3 or 4" ~ 3.5, x == "5 or 6" ~ 5.5,
    x == "7, 8 or 9" ~ 8, x == "10 or more" ~ 10,
    x == "-1" ~ -1, TRUE ~ NA_real_
  )
}

recode_alcohol_6plus <- function(x) {
  x <- as.character(x)
  x[x %in% c("Do not know")] <- NA
  x[x %in% c("Prefer not to answer", "Prefer not to say")] <- "-1"
  dplyr::case_when(
    x == "Never" ~ 0, x == "Less than monthly" ~ 0.5, x == "Monthly" ~ 1,
    x == "Weekly" ~ 4.3, x == "Daily or almost daily" ~ 30,
    x == "-1" ~ -1, TRUE ~ NA_real_
  )
}

for (v in find_like_cols(ukb_final, "alcohol_intake_freq"))        ukb_final[[v]] <- recode_alcohol_intake_freq(ukb_final[[v]])
for (v in find_like_cols(ukb_final, "alcohol_intake_typical_day")) ukb_final[[v]] <- recode_alcohol_typical_day(ukb_final[[v]])
for (v in find_like_cols(ukb_final, "alcohol_freq_6plus_units"))   ukb_final[[v]] <- recode_alcohol_6plus(ukb_final[[v]])

f   <- ukb_final$alcohol_intake_freq
u   <- ukb_final$alcohol_intake_typical_day
pna <- (!is.na(f) & f == -1) | (!is.na(u) & u == -1)
out <- rep(NA_real_, nrow(ukb_final))
out[pna]                           <- -1
out[!pna & !is.na(f) & !is.na(u)] <- f[!pna & !is.na(f) & !is.na(u)] * u[!pna & !is.na(f) & !is.na(u)]
ukb_final$total_unit_alcohol_per_week <- out

# Physical activity
clean_numeric_ukb <- function(x, unable_to_walk_to_zero = FALSE) {
  x <- as.character(x)
  x[x %in% c("Do not know","-999909999")] <- NA
  if (unable_to_walk_to_zero) x[x == "Unable to walk"] <- "0"
  x[x %in% c("Prefer not to answer", "Prefer not to say")] <- "-1"
  suppressWarnings(as.numeric(x))
}

freq4wk_to_week <- function(x) {
  x <- as.character(x)
  x[x %in% c("Do not know")] <- NA
  x[x %in% c("Prefer not to answer", "Prefer not to say")] <- "-1"
  dplyr::case_when(
    x == "-1"                                    ~ -1,
    x == "Once in the last 4 weeks"              ~ 0.25,
    x == "2-3 times in the last 4 weeks"         ~ 0.625,
    x == "Once a week"                           ~ 1,
    x == "2-3 times a week"                      ~ 2.5,
    x == "4-5 times a week"                      ~ 4.5,
    x == "Every day"                             ~ 7,
    TRUE ~ NA_real_
  )
}

durcat_to_min <- function(x) {
  x <- as.character(x)
  x[x %in% c("Do not know")] <- NA
  x[x %in% c("Prefer not to answer", "Prefer not to say")] <- "-1"
  dplyr::case_when(
    x == "-1"                                    ~ -1,
    x == "Less than 15 minutes"                  ~ 7.5,
    x == "Between 15 and 30 minutes"             ~ 22.5,
    x == "Between 30 minutes and 1 hour"         ~ 45,
    x == "Between 1 and 1.5 hours"               ~ 75,
    x == "Between 1.5 and 2 hours"               ~ 105,
    x == "Between 2 and 3 hours"                 ~ 150,
    x == "Over 3 hours"                          ~ 210,
    TRUE ~ NA_real_
  )
}

total_with_rules <- function(a, b) {
  a <- suppressWarnings(as.numeric(a)); b <- suppressWarnings(as.numeric(b))
  out <- a * b
  out[a == -1 | b == -1] <- -1
  out[(is.na(a) | is.na(b)) & !(a == -1 | b == -1)] <- NA_real_
  out
}

met_with_rules <- function(minutes_week, met) {
  x <- suppressWarnings(as.numeric(minutes_week))
  out <- met * x; out[x == -1] <- -1; out
}

get_canon_vec <- function(df, base) {
  cols <- find_like_cols(df, base)
  if (length(cols) == 0) return(rep(NA_real_, nrow(df)))
  if (length(cols) == 1) return(suppressWarnings(as.numeric(df[[cols[1]]])))
  X <- df[, cols, drop = FALSE]
  rowMeans(as.data.frame(lapply(X, function(z) suppressWarnings(as.numeric(z)))), na.rm = TRUE)
}

walk_cols <- find_like_cols(ukb_final, "number_of_daysweek_walked_10_minutes")

all_g1 <- unique(unlist(lapply(
  c("number_of_daysweek_walked_10_minutes","duration_of_walks",
    "number_of_daysweek_of_moderate_physical_activity","duration_of_moderate_activity",
    "number_of_daysweek_of_vigorous_physical_activity","duration_of_vigorous_activity"),
  function(b) find_like_cols(ukb_final, b))))
g1_nonwalk <- setdiff(all_g1, walk_cols)

if (length(g1_nonwalk) > 0) ukb_final[g1_nonwalk] <- lapply(ukb_final[g1_nonwalk], clean_numeric_ukb)
if (length(walk_cols)  > 0) ukb_final[walk_cols]  <- lapply(ukb_final[walk_cols],  clean_numeric_ukb, unable_to_walk_to_zero = TRUE)

cols_g2 <- unique(unlist(lapply(c("activity_heavy_diy_freq_4wk","activity_other_exercise_freq_4wk"), function(b) find_like_cols(ukb_final, b))))
cols_g3 <- unique(unlist(lapply(c("activity_heavy_diy_duration","activity_other_exercise_duration"),  function(b) find_like_cols(ukb_final, b))))
if (length(cols_g2) > 0) ukb_final[cols_g2] <- lapply(ukb_final[cols_g2], freq4wk_to_week)
if (length(cols_g3) > 0) ukb_final[cols_g3] <- lapply(ukb_final[cols_g3], durcat_to_min)

ukb_final$Total_activity_walk_minutes_week           <- total_with_rules(get_canon_vec(ukb_final,"number_of_daysweek_walked_10_minutes"),            get_canon_vec(ukb_final,"duration_of_walks"))
ukb_final$Total_activity_moderate_minutes_week       <- total_with_rules(get_canon_vec(ukb_final,"number_of_daysweek_of_moderate_physical_activity"), get_canon_vec(ukb_final,"duration_of_moderate_activity"))
ukb_final$Total_activity_vigorous_minutes_week       <- total_with_rules(get_canon_vec(ukb_final,"number_of_daysweek_of_vigorous_physical_activity"), get_canon_vec(ukb_final,"duration_of_vigorous_activity"))
ukb_final$Total_activity_heavy_diy_minutes_week      <- total_with_rules(get_canon_vec(ukb_final,"activity_heavy_diy_freq_4wk"),                      get_canon_vec(ukb_final,"activity_heavy_diy_duration"))
ukb_final$Total_activity_other_exercise_minutes_week <- total_with_rules(get_canon_vec(ukb_final,"activity_other_exercise_freq_4wk"),                 get_canon_vec(ukb_final,"activity_other_exercise_duration"))

ukb_final$MET_walk  <- met_with_rules(ukb_final$Total_activity_walk_minutes_week,     3.3)
ukb_final$MET_mod   <- met_with_rules(ukb_final$Total_activity_moderate_minutes_week, 4.0)
ukb_final$MET_vig   <- met_with_rules(ukb_final$Total_activity_vigorous_minutes_week, 8.0)
ukb_final$MET_total <- dplyr::case_when(
  ukb_final$MET_walk == -1 | ukb_final$MET_mod == -1 | ukb_final$MET_vig == -1 ~ -1,
  is.na(ukb_final$MET_walk) | is.na(ukb_final$MET_mod) | is.na(ukb_final$MET_vig) ~ NA_real_,
  TRUE ~ ukb_final$MET_walk + ukb_final$MET_mod + ukb_final$MET_vig
)

# Smoking
clean_ukb_smoking <- function(x) {
  x <- as.character(x)
  x[x == "Do not know"] <- NA
  x[x %in% c("Prefer not to answer", "Prefer not to say")] <- "-1"
  x
}

recode_cpd_score <- function(x) {
  x <- suppressWarnings(as.numeric(clean_ukb_smoking(x)))
  dplyr::case_when(x == -1 ~ -1, x <= 10 ~ 0, x <= 20 ~ 1, x <= 30 ~ 2, x > 30 ~ 3, TRUE ~ NA_real_)
}

recode_ttfc_score <- function(x) {
  x <- clean_ukb_smoking(x)
  dplyr::case_when(
    x == "Less than 5 minutes"                              ~ 3,
    x == "Between 5-15 minutes"                             ~ 2,
    x == "Between 30 minutes - 1 hour"                      ~ 1,
    x %in% c("Between 1 and 2 hours","Longer than 2 hours") ~ 0,
    x == "-1"                                               ~ -1,
    TRUE ~ NA_real_
  )
}

smoking_cols <- unique(unlist(lapply(
  c("smoking_age_started_former","smoking_cigarettes_daily_previous","smoking_age_stopped",
    "smoking_cigarettes_daily_current","smoking_time_to_first_cigarette","smoking_status"),
  function(b) find_like_cols(ukb_final, b))))

if (length(smoking_cols) > 0) ukb_final[smoking_cols] <- lapply(ukb_final[smoking_cols], clean_ukb_smoking)

v_cpd  <- find_like_cols(ukb_final, "smoking_cigarettes_daily_current")[1]
v_ttfc <- find_like_cols(ukb_final, "smoking_time_to_first_cigarette")[1]
v_stat <- find_like_cols(ukb_final, "smoking_status")[1]

CPD_score  <- if (!is.na(v_cpd))  recode_cpd_score(ukb_final[[v_cpd]])   else rep(NA_real_, nrow(ukb_final))
TTFC_score <- if (!is.na(v_ttfc)) recode_ttfc_score(ukb_final[[v_ttfc]]) else rep(NA_real_, nrow(ukb_final))
status_chr <- if (!is.na(v_stat)) as.character(ukb_final[[v_stat]])       else rep(NA_character_, nrow(ukb_final))

ukb_final$HSI <- dplyr::case_when(
  CPD_score == -1 | TTFC_score == -1 | status_chr == "-1" ~ -1,
  status_chr == "Never"                                    ~ 0,
  is.na(CPD_score) | is.na(TTFC_score)                    ~ NA_real_,
  TRUE                                                     ~ CPD_score + TTFC_score
)

v_cpd_prev  <- find_like_cols(ukb_final, "smoking_cigarettes_daily_previous")[1]
v_age_start <- find_like_cols(ukb_final, "smoking_age_started_former")[1]
v_age_stop  <- find_like_cols(ukb_final, "smoking_age_stopped")[1]

cpd_prev  <- if (!is.na(v_cpd_prev))  suppressWarnings(as.numeric(ukb_final[[v_cpd_prev]]))  else rep(NA_real_, nrow(ukb_final))
age_start <- if (!is.na(v_age_start)) suppressWarnings(as.numeric(ukb_final[[v_age_start]])) else rep(NA_real_, nrow(ukb_final))
age_stop  <- if (!is.na(v_age_stop))  suppressWarnings(as.numeric(ukb_final[[v_age_stop]]))  else rep(NA_real_, nrow(ukb_final))

ukb_final$pack_year_index <- dplyr::case_when(
  cpd_prev == -1 | age_start == -1 | age_stop == -1 | status_chr == "-1" ~ -1,
  status_chr == "Never"                                                  ~ 0,
  is.na(cpd_prev) | is.na(age_start) | is.na(age_stop)                   ~ NA_real_,
  (cpd_prev / 20) * (age_stop - age_start) < 0                           ~ NA_real_,
  TRUE ~ (cpd_prev / 20) * (age_stop - age_start)
)

# Beef intake score
recode_beef_score <- function(x) {
  x <- as.character(x)
  dplyr::case_when(
    x %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
    x == "Do not know"           ~ NA_real_,
    x == "Never"                 ~ 5,   x == "Less than once a week"  ~ 4,
    x == "Once a week"           ~ 3,   x == "2-4 times a week"       ~ 2,
    x == "5-6 times a week"      ~ 1,   x == "Once or more daily"     ~ 1,
    TRUE ~ NA_real_
  )
}
ukb_final$beef_intake_score <- recode_beef_score(ukb_final$beef_intake)

# Lab biomarker QC
lab_bio_ranges <- tribble(
  ~canonical,                    ~min,        ~max,
  "igf1",                        1.445,       126.766,
  "gamma_glutamyltransferase",   5,           1184.9,
  "creatinine",                  15.2653,    940.84,
  "aspartate_aminotransferase",  3.3,         947.2,
  "alanine_aminotransferase",    3.01,        495.19,
  "blood_wbc_count",             0,           389.7,
  "blood_rbc_count",             0.006,       7.911,
  "blood_hemoglobin_conc",       0.09,        22.27,
  "blood_hematocrit_pct",        0.05,        72.48,
  "blood_platelet_count",        0.3,         1821,
  "blood_platelet_volume_mean",  5.73,        16.5,
  "blood_platelet_distribution_width", 13.27, 20.2,
  "blood_reticulocyte_pct",      0,           90.909,
  "blood_reticulocyte_count",    0,           2.433,
  "blood_reticulocyte_volume_mean", 46,       249.45,
  "blood_reticulocyte_immature_fraction", 0,  1,
  "blood_reticulocyte_hls_pct",  0,           80,
  "blood_reticulocyte_hls_count", 0,          0.6,
  "biochem_apoa",                0.419,       2.5,
  "biochem_apob",                0.15432,     2.7124,
  "biochem_cholesterol",         0,           2994.94,
  "biochem_crp",                 0.08,        79.96,
  "biochem_glucose",             0.995,       36.813,
  "biochem_hba1c",               15,          515.2,
  "biochem_hdl",                 0.219,       4.401,
  "biochem_ldl_direct",          0.266,       9.797,
  "biochem_lipoa",               3.8,         189,
  "biochem_triglycerides",       0.231,       11.278,
  "biochem_sodium_urine",        10,          380.7
)

find_specific_cols <- function(df, base) {
  if (is.na(base) || !nzchar(base)) return(character(0))
  grep(paste0("^", base, "(\\.[0-9]+\\.[0-9]+)?$"), names(df), value = TRUE)
}

lab_pattern <- paste0("^(", paste(lab_bio_ranges$canonical, collapse = "|"), ")(\\.[0-9]+\\.[0-9]+)?$")
lab_cols    <- grep(lab_pattern, names(ukb_final), value = TRUE)

ukb_final[lab_cols] <- lapply(ukb_final[lab_cols], function(x) suppressWarnings(as.numeric(x)))

for (i in seq_len(nrow(lab_bio_ranges))) {
  base <- lab_bio_ranges$canonical[i]
  low  <- lab_bio_ranges$min[i]
  high <- lab_bio_ranges$max[i]
  cols <- find_specific_cols(ukb_final, base)
  if (length(cols) == 0) next
  for (v in cols) {
    x <- ukb_final[[v]]
    x[!is.na(x) & (x < low | x > high)] <- NA_real_
    ukb_final[[v]] <- x
  }
}

# Domain helpers
clean_text <- function(x) {
  x <- trimws(as.character(x))
  x[x == ""] <- NA
  x
}

clean_categorical <- function(x) {
  x <- clean_text(x)
  x[x %in% c("Prefer not to answer", "Prefer not to say")] <- "-1"
  x[x %in% c("Do not know", "Not applicable", "Not known")] <- NA
  x
}

clean_numeric <- function(x) {
  x <- clean_text(x)
  x[x %in% c("Prefer not to answer", "Prefer not to say", "Do not know", "Not applicable", "Not known")] <- NA
  suppressWarnings(as.numeric(x))
}

yn_recode <- function(x) {
  x <- clean_text(x)
  case_when(
    x == "Yes" ~ 1,
    x == "No" ~ 0,
    x %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
    x %in% c("Do not know", "Not applicable") ~ NA_real_,
    TRUE ~ NA_real_
  )
}

impact_recode <- function(x) {
  x <- clean_text(x)
  case_when(
    x == "Not at all" ~ 0,
    x == "A little" ~ 1,
    x == "Somewhat" ~ 2,
    x == "A lot" ~ 3,
    x %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
    x %in% c("Do not know", "Not applicable") ~ NA_real_,
    TRUE ~ NA_real_
  )
}

exposure_recode <- function(x) {
  x <- clean_text(x)
  case_when(
    x %in% c("Sometimes", "Often") ~ 1,
    x == "Rarely/never" ~ 0,
    x %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
    x %in% c("Do not know", "Not applicable") ~ NA_real_,
    TRUE ~ NA_real_
  )
}

collapse_multiselect <- function(df) {
  apply(df, 1, function(x) {
    x <- clean_text(x)
    x <- x[!is.na(x)]
    if (length(x) == 0) return(NA_character_)
    if (any(x %in% c("Prefer not to answer", "Prefer not to say"))) return("-1")
    x <- x[!x %in% c("Do not know", "Not applicable", "Not known")]
    if (length(x) == 0) return(NA_character_)
    paste(unique(x), collapse = ", ")
  })
}

# Social domain
leisure_cols <- find_cols(ukb_small, "social_leisure_activities")
if (length(leisure_cols) == 0) stop("No social_leisure_activities columns found")

social_leisure_activities <- collapse_multiselect(ukb_small[, leisure_cols, drop = FALSE])

visit_freq_raw <- clean_text(pull_col(ukb_small, "social_friend_family_visit_freq"))

visit_freq_score <- case_when(
  visit_freq_raw %in% c("Every day", "Daily") ~ 4,
  visit_freq_raw == "2-4 times a week" ~ 3,
  visit_freq_raw == "About once a week" ~ 2,
  visit_freq_raw == "About once a month" ~ 1,
  visit_freq_raw %in% c("Less often", "Never") ~ 0,
  visit_freq_raw %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
  visit_freq_raw == "Do not know" ~ NA_real_,
  TRUE ~ NA_real_
)

social_activity_score <- sapply(social_leisure_activities, function(x) {
  if (is.na(x)) return(NA_real_)
  if (x == "-1") return(-1)
  vals <- unlist(strsplit(x, ",\\s*"))
  vals <- vals[vals %in% c("Sports club or gym","Religious group","Pub or social club","Other group activity","Adult education class")]
  length(unique(vals))
})

visit_freq_temp <- ifelse(visit_freq_score == -1, NA, visit_freq_score)
activity_temp   <- ifelse(social_activity_score == -1, NA, social_activity_score)

visit_freq_z <- as.numeric(scale(visit_freq_temp))
activity_z   <- as.numeric(scale(activity_temp))

social_support_score <- rowMeans(cbind(visit_freq_z, activity_z), na.rm = TRUE)
social_support_score[is.nan(social_support_score)] <- NA
social_support_score[visit_freq_score == -1 | social_activity_score == -1] <- -1

social_df <- tibble(social_support_score = social_support_score)

# SES / occupational domain
ses_occ_df <- tibble(
  social_private_healthcare = clean_categorical(ukb_final$social_private_healthcare),
  ses_employment_status     = clean_categorical(ukb_final$ses_employment_status),
  ses_imd_england           = clean_numeric(ukb_final$ses_imd_england),
  ses_imd_wales             = clean_numeric(ukb_final$ses_imd_wales),
  ses_imd_scotland          = clean_numeric(ukb_final$ses_imd_scotland)
)

# Mental health domain
mh_df <- tibble(
  mh_mood_swings           = yn_recode(ukb_final$mh_mood_swings),
  mh_miserableness         = yn_recode(ukb_final$mh_miserableness),
  mh_irritability          = yn_recode(ukb_final$mh_irritability),
  mh_sensitivity_hurt      = yn_recode(ukb_final$mh_sensitivity_hurt),
  mh_fed_up                = yn_recode(ukb_final$mh_fed_up),
  mh_nervous               = yn_recode(ukb_final$mh_nervous),
  mh_worrier_anxious       = yn_recode(ukb_final$mh_worrier_anxious),
  mh_tense_highly_strung   = yn_recode(ukb_final$mh_tense_highly_strung),
  mh_worry_after_embarrass = yn_recode(ukb_final$mh_worry_after_embarrass),
  mh_suffer_nerves         = yn_recode(ukb_final$mh_suffer_nerves),
  mh_loneliness            = yn_recode(ukb_final$mh_loneliness),
  mh_guilt                 = yn_recode(ukb_final$mh_guilt)
)

mh_seen_gp_nerves    <- yn_recode(ukb_final$mh_seen_gp_nerves)
mh_seen_psychiatrist <- yn_recode(ukb_final$mh_seen_psychiatrist)

mh_df$mh_seen_clinician <- case_when(
  mh_seen_gp_nerves == 1 | mh_seen_psychiatrist == 1 ~ 1,
  mh_seen_gp_nerves == 0 & mh_seen_psychiatrist == 0 ~ 0,
  mh_seen_gp_nerves == -1 | mh_seen_psychiatrist == -1 ~ -1,
  TRUE ~ NA_real_
)

anxiety_df <- tibble(
  mh_anxiety_worst_muscles_tense          = yn_recode(ukb_final$mh_anxiety_worst_muscles_tense),
  mh_anxiety_worst_impact_roles           = impact_recode(ukb_final$mh_anxiety_worst_impact_roles),
  mh_anxiety_worst_difficulty_concentrate = yn_recode(ukb_final$mh_anxiety_worst_difficulty_concentrate),
  mh_anxiety_ever_worried_month           = yn_recode(ukb_final$mh_anxiety_ever_worried_month),
  mh_anxiety_worst_more_irritable         = yn_recode(ukb_final$mh_anxiety_worst_more_irritable),
  mh_anxiety_worst_keyed_up               = yn_recode(ukb_final$mh_anxiety_worst_keyed_up),
  mh_anxiety_worried_more_than_others     = yn_recode(ukb_final$mh_anxiety_worried_more_than_others),
  mh_anxiety_worst_restless               = yn_recode(ukb_final$mh_anxiety_worst_restless),
  mh_anxiety_worst_sleep_trouble          = yn_recode(ukb_final$mh_anxiety_worst_sleep_trouble),
  mh_anxiety_professional_informed        = yn_recode(ukb_final$mh_anxiety_professional_informed),
  mh_anxiety_worst_easily_tired           = yn_recode(ukb_final$mh_anxiety_worst_easily_tired)
)

anx_temp <- anxiety_df
pna_row  <- apply(anx_temp, 1, function(x) any(x == -1, na.rm = TRUE))
anx_temp[anx_temp == -1] <- NA

anxiety_score <- rowSums(anx_temp, na.rm = TRUE)
answered_n    <- rowSums(!is.na(anx_temp))
anxiety_score[answered_n < 6 & !pna_row] <- NA
anxiety_score[pna_row] <- -1

dep_single <- yn_recode(ukb_final$mh_depression_single_episode_probable)
dep_mod    <- yn_recode(ukb_final$mh_depression_recurrent_moderate)
dep_severe <- yn_recode(ukb_final$mh_depression_recurrent_severe)
dep_stress <- yn_recode(ukb_final$mh_depression_stressful_event)

bipolar_dep_status_raw <- clean_text(ukb_final$mh_bipolar_major_depression_status)
bipolar_dep_status <- case_when(
  bipolar_dep_status_raw == "No Bipolar or Depression" ~ 0,
  bipolar_dep_status_raw == "Single Probable major depression episode" ~ 1,
  bipolar_dep_status_raw == "Probable Recurrent major depression (moderate)" ~ 2,
  bipolar_dep_status_raw == "Probable Recurrent major depression (severe)" ~ 3,
  bipolar_dep_status_raw %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
  bipolar_dep_status_raw == "Do not know" ~ NA_real_,
  TRUE ~ NA_real_
)

dep_temp <- tibble(
  mh_depression_single_episode_probable = dep_single,
  mh_depression_recurrent_moderate      = dep_mod,
  mh_depression_recurrent_severe        = dep_severe,
  mh_bipolar_major_depression_status    = bipolar_dep_status,
  mh_depression_stressful_event         = dep_stress
)

pna_row_dep <- apply(dep_temp, 1, function(x) any(x == -1, na.rm = TRUE))
dep_temp[dep_temp == -1] <- NA

depression_score <- rowSums(dep_temp, na.rm = TRUE)
depression_score[pna_row_dep] <- -1

sleep_numeric <- tibble(
  sleep_falling_asleep    = yn_recode(ukb_final$sleep_trouble_falling),
  sleep_sleeping_too_much = yn_recode(ukb_final$sleep_sleeping_too_much),
  sleep_waking_early      = yn_recode(ukb_final$sleep_waking_early)
)

pna_sleep <- apply(sleep_numeric, 1, function(x) any(x == -1, na.rm = TRUE))

sleep_numeric_for_score <- sleep_numeric
sleep_numeric_for_score[sleep_numeric_for_score == -1] <- NA
sleep_numeric_for_score <- as.data.frame(lapply(sleep_numeric_for_score, as.numeric))

sleep_symptom_count <- rowSums(sleep_numeric_for_score, na.rm = TRUE)
answered_items      <- rowSums(!is.na(sleep_numeric_for_score))
sleep_symptom_count[answered_items < 2 & !pna_sleep] <- NA
sleep_symptom_count[pna_sleep] <- -1

mh_df <- mh_df %>%
  mutate(
    anxiety_score       = anxiety_score,
    depression_score    = depression_score,
    sleep_symptom_count = sleep_symptom_count
  )

# Addiction domain
addiction_df <- tibble(
  mh_addiction_substance_behaviour = yn_recode(ukb_final$mh_addiction_substance_behaviour)
)

# Health / comorbidities domain
dx_diabetes_gestational_only_raw <- clean_text(ukb_final$dx_diabetes_gestational_only)
dx_diabetes_gestational_only <- case_when(
  dx_diabetes_gestational_only_raw == "Yes" ~ 1,
  dx_diabetes_gestational_only_raw == "No" ~ 0,
  dx_diabetes_gestational_only_raw %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
  dx_diabetes_gestational_only_raw %in% c("Not applicable", "Do not know") ~ NA_real_,
  TRUE ~ NA_real_
)

dx_cancer_raw <- clean_text(ukb_final$dx_cancer)
dx_cancer <- case_when(
  grepl("^Yes", dx_cancer_raw, ignore.case = TRUE) ~ 1,
  grepl("^No",  dx_cancer_raw, ignore.case = TRUE) ~ 0,
  dx_cancer_raw %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
  dx_cancer_raw %in% c("Do not know", "Not applicable") ~ NA_real_,
  TRUE ~ NA_real_
)

med_raw <- clean_text(ukb_final$med_cholesterol_bp_diabetes_hormones)
med_cholesterol_bp_diabetes_hormones <- case_when(
  med_raw %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
  med_raw %in% c("Do not know", "Not applicable") | is.na(med_raw) ~ NA_real_,
  med_raw == "None of the above" ~ 0,
  TRUE ~ 1
)

pain_cols <- grep("^pain_medication\\.[0-9]+\\.[0-9]+$", names(ukb_small), value = TRUE)
if (length(pain_cols) == 0) pain_cols <- grep("^pain_medication\\.", names(ukb_small), value = TRUE)

pain_medication <- if (length(pain_cols) > 0) {
  collapse_multiselect(ukb_small[, pain_cols, drop = FALSE])
} else {
  rep(NA_character_, nrow(ukb_small))
}

pain_any_med <- case_when(
  pain_medication == "-1" ~ -1,
  is.na(pain_medication)  ~ NA_real_,
  str_detect(pain_medication, fixed("None of the above")) ~ 0,
  TRUE ~ 1
)

mental_categories <- clean_categorical(pull_col(ukb_final, "mental_categories", required = FALSE))
mental_categories[mental_categories == "Other"] <- NA

health_df <- tibble(
  dx_diabetes_gestational_only          = dx_diabetes_gestational_only,
  dx_cancer                             = dx_cancer,
  med_cholesterol_bp_diabetes_hormones  = med_cholesterol_bp_diabetes_hormones,
  pain_any_med                          = pain_any_med,
  cancer_occurrences_reported           = clean_numeric(ukb_final$cancer_occurrences_reported),
  cancer_histology                      = clean_categorical(ukb_final$cancer_histology),
  cancer_behaviour                      = clean_categorical(ukb_final$cancer_behaviour),
  mental_categories                     = mental_categories,
  mh_psychiatric_care_history_admission = clean_categorical(ukb_final$mh_psychiatric_care_history_admission)
)

# Occupational health domain
exposure_df <- tibble(
  occ_chemical_fumes_exposed        = exposure_recode(ukb_final$occ_chemical_fumes),
  occ_cigarette_smoke_exposed       = exposure_recode(ukb_final$occ_cigarette_smoke),
  occ_paints_thinners_glues_exposed = exposure_recode(ukb_final$occ_paints_thinners_glues),
  occ_pesticides_exposed            = exposure_recode(ukb_final$occ_pesticides),
  occ_diesel_exhaust_exposed        = exposure_recode(ukb_final$occ_diesel_exhaust)
)

occ_workplace_pollutant_exposed <- case_when(
  apply(exposure_df, 1, function(x) any(x == -1, na.rm = TRUE)) ~ -1,
  apply(exposure_df, 1, function(x) all(is.na(x))) ~ NA_real_,
  rowSums(exposure_df == 1, na.rm = TRUE) > 0 ~ 1,
  rowSums(exposure_df == 0, na.rm = TRUE) > 0 ~ 0,
  TRUE ~ NA_real_
)

occ_health_df <- tibble(
  occ_workplace_pollutant_exposed = occ_workplace_pollutant_exposed,
  occ_breathing_problems          = clean_categorical(ukb_final$occ_breathing_problems)
)

# Bind all domains
domain_df <- bind_cols(social_df, sleep_numeric, ses_occ_df, mh_df, addiction_df, health_df, occ_health_df)
domain_df <- domain_df[, !duplicated(names(domain_df)), drop = FALSE]

col_na_pct <- sapply(domain_df, function(x) mean(is.na(x)) * 100)
print(col_na_pct)

# Drop columns with >50% missing
domain_df <- domain_df[, colMeans(is.na(domain_df)) <= 0.5, drop = FALSE]

ukb_final <- ukb_final[, !duplicated(names(ukb_final)), drop = FALSE]
ukb_final <- ukb_final[, !names(ukb_final) %in% names(domain_df), drop = FALSE]
ukb_final <- bind_cols(ukb_final, domain_df)

# Drop intermediate social columns
cols_to_remove <- grep(
  "^(social_leisure_activities_|social_friend_family_visit_freq$|mh_seen_gp_nerves$|mh_seen_psychiatrist$)",
  names(ukb_final), value = TRUE)
ukb_final <- ukb_final[, !names(ukb_final) %in% cols_to_remove]

# Recode anxiety items and recompute score
anxiety_cols <- grep("^mh_anxiety_", names(ukb_final), value = TRUE)

ukb_final[anxiety_cols] <- lapply(ukb_final[anxiety_cols], function(x) {
  x <- trimws(as.character(x))
  dplyr::case_when(
    x == "Yes" ~ 1,
    x == "No"  ~ 0,
    x %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
    x == "Do not know" ~ NA_real_,
    TRUE ~ NA_real_
  )
})

anxiety_df  <- ukb_final[, anxiety_cols]
pna_row     <- apply(anxiety_df, 1, function(x) any(x == -1, na.rm = TRUE))
anxiety_temp <- anxiety_df
anxiety_temp[anxiety_temp == -1] <- NA
anxiety_score  <- rowSums(anxiety_temp, na.rm = TRUE)
answered_n     <- rowSums(!is.na(anxiety_temp))
anxiety_score[answered_n < 6 & !pna_row] <- NA
anxiety_score[pna_row] <- -1
ukb_final$anxiety_score <- anxiety_score

ukb_final <- ukb_final[, !names(ukb_final) %in% grep("^mh_anxiety_", names(ukb_final), value = TRUE)]

# Drop raw depression columns
ukb_final <- ukb_final[, !names(ukb_final) %in%
                         grep("^(mh_depression_|mh_bipolar_major_depression_status$)", names(ukb_final), value = TRUE)]

# Recode remaining binary mental health items
cols_to_recode <- grep(
  "^(sleep_trouble_falling|sleep_sleeping_too_much|sleep_waking_early|mh_addiction_substance_behaviour)$",
  names(ukb_final), value = TRUE)

ukb_final[cols_to_recode] <- lapply(ukb_final[cols_to_recode], function(x) {
  x <- trimws(as.character(x))
  dplyr::case_when(
    x == "Yes" ~ 1,
    x == "No"  ~ 0,
    x %in% c("Prefer not to answer", "Prefer not to say") ~ -1,
    x == "Do not know" ~ NA_real_,
    TRUE ~ NA_real_
  )
})

# Mental categories binary flag
ukb_final$mh_mental_categories_binary <- dplyr::case_when(
  ukb_final$mental_categories_1 %in% c("Mental illness","Mental impairment","Psychopathic disorder","Severe mental impairment","Other") ~ 1,
  ukb_final$mental_categories_1 == "Not applicable" ~ 0,
  ukb_final$mental_categories_1 == "Not known"      ~ NA_real_,
  TRUE ~ NA_real_
)

# Drop raw occupational and mental category columns
ukb_final <- ukb_final[, !names(ukb_final) %in%
                         grep("^(mental_categories_|occ_chemical_fumes$|occ_cigarette_smoke$|occ_paints_thinners_glues$|occ_pesticides$|occ_diesel_exhaust$)",
                              names(ukb_final), value = TRUE)]

# Recode satisfaction variables
mh_vars <- c("mh_work_satisfaction","mh_health_satisfaction","mh_family_satisfaction",
             "mh_friendships_satisfaction","mh_financial_satisfaction")

ukb_final <- ukb_final %>%
  mutate(across(all_of(mh_vars), ~ {
    x <- trimws(as.character(.))
    x[x %in% c("Prefer not to answer", "Prefer not to say")] <- "-1"
    x[x == "Do not know"] <- NA
    suppressWarnings(as.numeric(x))
  }))

# Clean satisfaction in ukb_small
satisfaction_cols <- grep("satisfac", names(ukb_small), value = TRUE)
ukb_small[satisfaction_cols] <- lapply(ukb_small[satisfaction_cols], function(x) {
  x <- clean_text(x)
  x[x %in% c("Do not know", "Prefer not to answer", "Prefer not to say")] <- NA
  x
})

# Re-merge cleaned domain variables
domain_df <- domain_df[, !duplicated(names(domain_df)), drop = FALSE]
names(domain_df) <- sub("\\.[0-9]+\\.[0-9]+$", "", names(domain_df))
domain_df <- domain_df[, colMeans(is.na(domain_df)) <= 0.5, drop = FALSE]

ukb_final <- ukb_final[, !duplicated(names(ukb_final)), drop = FALSE]
domain_names_clean <- names(domain_df)
cols_to_drop <- names(ukb_final) %in% domain_names_clean |
  sub("\\.[0-9]+\\.[0-9]+$", "", names(ukb_final)) %in% domain_names_clean
ukb_final <- ukb_final[, !cols_to_drop, drop = FALSE]
ukb_final <- bind_cols(ukb_final, domain_df)

# DASH score
dash_score <- function(...) {
  mat <- cbind(...)
  ifelse(
    rowSums(mat == -1, na.rm = TRUE) > 0, -1,
    ifelse(rowSums(is.na(mat)) > 0, NA_real_, rowSums(mat))
  )
}

ukb_final$DASH_score <- dash_score(
  ukb_final$diet_carbohydrate_score,
  ukb_final$dietary_fibre_score,
  ukb_final$sugars_score,
  ukb_final$saturated_fat_score,
  ukb_final$polyunsaturated_fat_score,
  ukb_final$veg_quintile_score,
  ukb_final$fruit_quintile_score,
  ukb_final$beef_intake_score
)

# Drop raw diet columns
diet_raw <- c("diet_carbohydrate","dietary_fibre","sugars","saturated_fat","polyunsaturated_fat","beef_intake",
              "diet24_veg_mixed_intake","diet24_veg_pieces_intake","diet24_veg_other_intake",
              "diet_veg_cooked_intake","diet_veg_salad_raw_intake","diet_veg_consumers",
              "diet_fruit_fresh_intake","diet_fruit_dried_intake","diet_fruit_consumers",
              "diet24_fruit_dried_intake","diet24_fruit_mixed_intake")

ukb_final <- ukb_final %>% dplyr::select(-any_of(diet_raw))

# Sleep duration QC
sleep_ranges <- tribble(~canonical, ~min, ~max, "sleep_duration", 1, 23)

sleep_pattern <- paste0("^(", paste(sleep_ranges$canonical, collapse = "|"), ")(\\.[0-9]+\\.[0-9]+)?$")
sleep_cols    <- grep(sleep_pattern, names(ukb_final), value = TRUE)

ukb_final[sleep_cols] <- lapply(ukb_final[sleep_cols], function(x) {
  x <- as.character(x)
  x[x %in% c("Prefer not to answer", "Prefer not to say")] <- -1
  x[x == "Do not know"] <- NA
  suppressWarnings(as.numeric(x))
})

for (i in seq_len(nrow(sleep_ranges))) {
  base <- sleep_ranges$canonical[i]
  low  <- sleep_ranges$min[i]
  high <- sleep_ranges$max[i]
  cols <- find_specific_cols(ukb_final, base)
  if (length(cols) == 0) next
  for (v in cols) ukb_final[[v]] <- clean_apply_range(ukb_final[[v]], low, high)
}

# Drop intermediate/raw variables
drop_vars <- c(
  "diet_carbohydrate_score","dietary_fibre_score","sugars_score","saturated_fat_score",
  "polyunsaturated_fat_score","veg_quintile_score","fruit_quintile_score","beef_intake_score",
  "Total_activity_walk_minutes_week","Total_activity_moderate_minutes_week",
  "Total_activity_vigorous_minutes_week","Total_activity_heavy_diy_minutes_week",
  "Total_activity_other_exercise_minutes_week",
  "number_of_daysweek_walked_10_minutes","duration_of_walks",
  "number_of_daysweek_of_moderate_physical_activity","duration_of_moderate_activity",
  "number_of_daysweek_of_vigorous_physical_activity","duration_of_vigorous_activity",
  "activity_heavy_diy_freq_4wk","activity_heavy_diy_duration",
  "activity_other_exercise_freq_4wk","activity_other_exercise_duration",
  "alcohol_intake_freq","alcohol_intake_typical_day",
  "smoking_age_started_former","smoking_cigarettes_daily_previous","smoking_age_stopped",
  "smoking_cigarettes_daily_current","smoking_time_to_first_cigarette","smoking_status",
  "date_of_attending_centre","cvd_date","date_of_death"
)

ukb_final <- ukb_final %>% dplyr::select(-any_of(drop_vars))

names(ukb_final) <- gsub("\\.\\.\\.[0-9]+$", "", names(ukb_final))

# Save
saveRDS(ukb_final, "../outputs/ukb_processed.rds")

print("Preprocessing finished")