rm(list = ls())

suppressPackageStartupMessages({
  library(randomForest)
  library(missForestPredict)
  library(dplyr)
  library(data.table)
})

set.seed(100000000)

# -------------------------------
# 1. Load data
# -------------------------------
ukb <- readRDS("../../1_recoding_extraction_preprocessing/outputs/ukb_filtered_NA.rds")
ukb <- as.data.frame(ukb)
ukb <- ukb[, !names(ukb) %in% "cancer_histology", drop = FALSE]
# -------------------------------
# 2. Protect variables
# -------------------------------
protected_vars <- intersect(c(
  "date_of_death",
  "cvd",
  "eid"
), names(ukb))

# -------------------------------
# 3. Automatically classify variable classes
# -------------------------------
classify_variables <- function(df,
                               protected_vars = character(),
                               low_unique_threshold = 10,
                               index_name_patterns = c("_score$", "^HSI$"),
                               force_numeric_patterns = c("_z_score$", "^energy$")) {
  
  numeric_vars <- c()
  categorical_vars <- c()
  index_vars <- c()
  
  candidate_vars <- setdiff(names(df), protected_vars)
  
  for (v in candidate_vars) {
    x <- df[[v]]
    x_no_na <- x[!is.na(x)]
    n_unique <- length(unique(x_no_na))
    
    # -------------------------
    # FORCE NUMERIC 
    # -------------------------
    is_force_numeric <- any(sapply(force_numeric_patterns, function(p) grepl(p, v)))
    
    if (is_force_numeric) {
      numeric_vars <- c(numeric_vars, v)
      next
    }
    
    # -------------------------
    # 1. index vars
    # -------------------------
    is_index <- any(sapply(index_name_patterns, function(p) grepl(p, v)))
    
    if (is_index) {
      index_vars <- c(index_vars, v)
      next
    }
    
    # -------------------------
    # 2. factor / character
    # -------------------------
    if (is.factor(x) || is.character(x)) {
      categorical_vars <- c(categorical_vars, v)
      next
    }
    
    # -------------------------
    # 3. numeric / integer
    # -------------------------
    if (is.numeric(x) || is.integer(x)) {
      if (n_unique <= low_unique_threshold) {
        categorical_vars <- c(categorical_vars, v)
      } else {
        numeric_vars <- c(numeric_vars, v)
      }
      next
    }
    
    # -------------------------
    # 4. fallback
    # -------------------------
    categorical_vars <- c(categorical_vars, v)
  }
  
  list(
    numeric_vars = unique(numeric_vars),
    categorical_vars = unique(categorical_vars),
    index_vars = unique(index_vars)
  )
}

classified <- classify_variables(
  df = ukb,
  protected_vars = protected_vars,
  low_unique_threshold = 10,
  index_name_patterns = c("_score$", "^HSI$")
)

numeric_vars <- classified$numeric_vars
categorical_vars <- classified$categorical_vars
index_vars <- classified$index_vars

all_classified <- unique(c(
  protected_vars,
  numeric_vars,
  categorical_vars,
  index_vars
))

cat("Unclassified variables:\n")
print(setdiff(names(ukb), all_classified))

cat("\nMissing classified variables in dataset:\n")
print(setdiff(all_classified, names(ukb)))

cat("\nNumeric vars:\n")
print(numeric_vars)

cat("\nCategorical vars:\n")
print(categorical_vars)

cat("\nIndex vars:\n")
print(index_vars)

# -------------------------------
# 4. Define allowed ranges for index variables
# -------------------------------
index_ranges <- list(
  DASH_score = c(0, 40),
  HSI = c(0, 6)
)
index_ranges <- index_ranges[names(index_ranges) %in% index_vars]

# -------------------------------
# 5. Safety checks
# -------------------------------
cat("Protected vars:", length(protected_vars), "\n")
print(protected_vars)

cat("\nNumeric vars:", length(numeric_vars), "\n")
print(numeric_vars)

cat("\nCategorical vars:", length(categorical_vars), "\n")
print(categorical_vars)

cat("\nIndex vars:", length(index_vars), "\n")
print(index_vars)

cat("\nOverlap numeric & categorical:\n")
print(intersect(numeric_vars, categorical_vars))

cat("\nOverlap numeric & index:\n")
print(intersect(numeric_vars, index_vars))

cat("\nOverlap categorical & index:\n")
print(intersect(categorical_vars, index_vars))

cat("\nOverlap protected & numeric:\n")
print(intersect(protected_vars, numeric_vars))

cat("\nOverlap protected & categorical:\n")
print(intersect(protected_vars, categorical_vars))

cat("\nOverlap protected & index:\n")
print(intersect(protected_vars, index_vars))

# -------------------------------
# 6. Build dataset for splitting and analysis
# -------------------------------
analysis_vars <- c(numeric_vars, categorical_vars, index_vars)
analysis_vars <- unique(setdiff(analysis_vars, protected_vars))

needed_vars <- unique(c("cvd", protected_vars, analysis_vars))
needed_vars <- needed_vars[needed_vars %in% names(ukb)]

df <- ukb[, needed_vars, drop = FALSE]

# -------------------------------
# 7. Convert variable classes
# -------------------------------
for (v in categorical_vars) {
  if (v %in% names(df)) {
    df[[v]] <- as.factor(df[[v]])
  }
}

for (v in numeric_vars) {
  if (v %in% names(df)) {
    df[[v]] <- suppressWarnings(as.numeric(as.character(df[[v]])))
  }
}

for (v in index_vars) {
  if (v %in% names(df)) {
    df[[v]] <- suppressWarnings(as.numeric(as.character(df[[v]])))
  }
}

# -------------------------------
# 8. Stratified split by cvd: 70 / 15 / 15
# -------------------------------
if (!("cvd" %in% names(df))) {
  stop("cvd column is required for stratified splitting.")
}

idx_all <- seq_len(nrow(df))
idx_cvd1 <- idx_all[df$cvd == 1]
idx_cvd0 <- idx_all[df$cvd == 0]

split_one_group <- function(idx, p_train = 0.70, p_val = 0.15) {
  n <- length(idx)
  idx <- sample(idx, n)
  
  n_train <- floor(n * p_train)
  n_val   <- floor(n * p_val)
  n_test  <- n - n_train - n_val
  
  list(
    train = idx[seq_len(n_train)],
    val   = idx[seq(from = n_train + 1, length.out = n_val)],
    test  = idx[seq(from = n_train + n_val + 1, length.out = n_test)]
  )
}

sp1 <- split_one_group(idx_cvd1, 0.70, 0.15)
sp0 <- split_one_group(idx_cvd0, 0.70, 0.15)

train_idx <- sample(c(sp1$train, sp0$train))
val_idx   <- sample(c(sp1$val,   sp0$val))
test_idx  <- sample(c(sp1$test,  sp0$test))

train_df <- df[train_idx, , drop = FALSE]
val_df   <- df[val_idx, , drop = FALSE]
test_df  <- df[test_idx, , drop = FALSE]

cat("\nSplit sizes:\n")
cat("Train:", nrow(train_df), "\n")
cat("Validation:", nrow(val_df), "\n")
cat("Test:", nrow(test_df), "\n")

cat("\nCVD distribution:\n")
cat("Train:\n")
print(table(train_df$cvd, useNA = "ifany"))
cat("Validation:\n")
print(table(val_df$cvd, useNA = "ifany"))
cat("Test:\n")
print(table(test_df$cvd, useNA = "ifany"))

# -------------------------------
# 9. Separate protected and analysis subsets
# -------------------------------
train_protected <- train_df[, intersect(protected_vars, names(train_df)), drop = FALSE]
val_protected   <- val_df[,   intersect(protected_vars, names(val_df)),   drop = FALSE]
test_protected  <- test_df[,  intersect(protected_vars, names(test_df)),  drop = FALSE]

train_analysis <- train_df[, intersect(analysis_vars, names(train_df)), drop = FALSE]
val_analysis   <- val_df[,   intersect(analysis_vars, names(val_df)),   drop = FALSE]
test_analysis  <- test_df[,  intersect(analysis_vars, names(test_df)),  drop = FALSE]

# -------------------------------
# 10. Optional checks before imputation
# -------------------------------
cat("\nNA count before imputation - train:\n")
print(sort(colSums(is.na(train_analysis)), decreasing = TRUE))

cat("\nVariable classes before imputation - train:\n")
print(sapply(train_analysis, class))

# -------------------------------
# 11. Random Forest imputation using missForestPredict
# -------------------------------
run_mfp_train <- function(dat, num.trees = 100, maxiter = 5) {
  missForestPredict::missForest(
    xmis = dat,
    num.trees = num.trees,
    maxiter = maxiter,
    verbose = TRUE,
    save_models = TRUE
  )
}

run_mfp_apply <- function(new_dat, train_imp_obj) {
  missForestPredict::missForestPredict(
    missForestObj = train_imp_obj,
    newdata = new_dat
  )
}

extract_imputed_df <- function(obj, obj_name = "object") {
  if (is.data.frame(obj)) {
    message(obj_name, " returned a data.frame directly.")
    return(obj)
  }
  
  if (is.list(obj) && "ximp" %in% names(obj) && is.data.frame(obj$ximp)) {
    message(obj_name, " returned a list; using $ximp.")
    return(obj$ximp)
  }
  
  stop(
    obj_name,
    " does not contain an imputed data.frame in an expected format. ",
    "Check missForestPredict return structure."
  )
}

imp_train_obj <- run_mfp_train(
  dat = train_analysis,
  num.trees = 100,
  maxiter = 5
)

cat("After run_mfp_train\n")
print(class(imp_train_obj))

if (is.list(imp_train_obj)) {
  print(names(imp_train_obj))
}

train_imp <- extract_imputed_df(imp_train_obj, "imp_train_obj")
cat("train_imp extracted successfully\n")
print(dim(train_imp))
print(sum(is.na(train_imp)))

imp_val_obj <- run_mfp_apply(
  new_dat = val_analysis,
  train_imp_obj = imp_train_obj
)

imp_test_obj <- run_mfp_apply(
  new_dat = test_analysis,
  train_imp_obj = imp_train_obj
)

val_imp  <- extract_imputed_df(imp_val_obj,  "imp_val_obj")
test_imp <- extract_imputed_df(imp_test_obj, "imp_test_obj")

cat("\nImputed data dimensions:\n")
cat("Train:", dim(train_imp), "\n")
cat("Validation:", dim(val_imp), "\n")
cat("Test:", dim(test_imp), "\n")

# -------------------------------
# 12. Basic structure checks after imputation
# -------------------------------
stopifnot(is.data.frame(train_imp))
stopifnot(is.data.frame(val_imp))
stopifnot(is.data.frame(test_imp))

# -------------------------------
# 13. Constrain index variables
# -------------------------------
constrain_index_integer <- function(x, min_val, max_val) {
  x <- pmax(x, min_val)
  x <- pmin(x, max_val)
  x <- round(x)
  x
}

apply_index_constraints <- function(df_in, index_ranges) {
  for (v in names(index_ranges)) {
    if (v %in% names(df_in)) {
      rng <- index_ranges[[v]]
      df_in[[v]] <- constrain_index_integer(df_in[[v]], rng[1], rng[2])
    }
  }
  df_in
}

train_imp <- apply_index_constraints(train_imp, index_ranges)
val_imp   <- apply_index_constraints(val_imp, index_ranges)
test_imp  <- apply_index_constraints(test_imp, index_ranges)

# -------------------------------
# 14. Restore categorical variables as factor
# -------------------------------
restore_factors <- function(df_in, categorical_vars) {
  for (v in categorical_vars) {
    if (v %in% names(df_in)) {
      df_in[[v]] <- as.factor(df_in[[v]])
    }
  }
  df_in
}

train_imp <- restore_factors(train_imp, categorical_vars)
val_imp   <- restore_factors(val_imp, categorical_vars)
test_imp  <- restore_factors(test_imp, categorical_vars)

# -------------------------------
# 15. Bind protected vars back
# -------------------------------
ukb_train_imputed <- cbind(train_protected, train_imp)
ukb_val_imputed   <- cbind(val_protected,   val_imp)
ukb_test_imputed  <- cbind(test_protected,  test_imp)

final_col_order_train <- intersect(names(ukb), names(ukb_train_imputed))
final_col_order_val   <- intersect(names(ukb), names(ukb_val_imputed))
final_col_order_test  <- intersect(names(ukb), names(ukb_test_imputed))

ukb_train_imputed <- ukb_train_imputed[, final_col_order_train, drop = FALSE]
ukb_val_imputed   <- ukb_val_imputed[,   final_col_order_val,   drop = FALSE]
ukb_test_imputed  <- ukb_test_imputed[,  final_col_order_test,  drop = FALSE]

# -------------------------------
# 16. Add data_type column
# -------------------------------
ukb_train_imputed$data_type <- factor("train", levels = c("train", "validation", "test"))
ukb_val_imputed$data_type   <- factor("validation", levels = c("train", "validation", "test"))
ukb_test_imputed$data_type  <- factor("test", levels = c("train", "validation", "test"))

# -------------------------------
# 17. Merge all datasets
# -------------------------------
ukb_imputed_all <- bind_rows(
  ukb_train_imputed,
  ukb_val_imputed,
  ukb_test_imputed
)

col_order_all <- c(
  setdiff(c("date_of_attending_centre", "cvd_date", "date_of_death", "cvd", "data_type"), character(0)),
  setdiff(names(ukb_imputed_all), c("date_of_attending_centre", "cvd_date", "date_of_death", "cvd", "data_type"))
)
col_order_all <- col_order_all[col_order_all %in% names(ukb_imputed_all)]
ukb_imputed_all <- ukb_imputed_all[, col_order_all, drop = FALSE]

# -------------------------------
# 18. Final checks before score calculation
# -------------------------------
cat("\nFinal dimensions:\n")
cat("Train:", dim(ukb_train_imputed), "\n")
cat("Validation:", dim(ukb_val_imputed), "\n")
cat("Test:", dim(ukb_test_imputed), "\n")
cat("Combined:", dim(ukb_imputed_all), "\n")

cat("\nAny NA left?\n")
cat("Train:", anyNA(ukb_train_imputed), "\n")
cat("Validation:", anyNA(ukb_val_imputed), "\n")
cat("Test:", anyNA(ukb_test_imputed), "\n")
cat("Combined:", anyNA(ukb_imputed_all), "\n")

cat("\nIndex ranges after constraint:\n")
for (v in index_vars) {
  if (v %in% names(ukb_imputed_all)) {
    cat("\n", v, ":\n", sep = "")
    cat("Train range: ")
    print(range(ukb_train_imputed[[v]], na.rm = TRUE))
    cat("Validation range: ")
    print(range(ukb_val_imputed[[v]], na.rm = TRUE))
    cat("Test range: ")
    print(range(ukb_test_imputed[[v]], na.rm = TRUE))
  }
}

# -------------------------------
# 19. TRAIN-based thresholds for CVH
# -------------------------------
make_percentile_thresholds <- function(x, probs) {
  quantile(x, probs = probs, na.rm = TRUE, type = 7)
}

apply_percentile_score <- function(x, thresholds, scores, higher_better = TRUE) {
  if (length(scores) != (length(thresholds) + 1)) {
    stop("Length of scores must equal length(thresholds) + 1")
  }
  
  out <- rep(NA_real_, length(x))
  ok <- !is.na(x)
  
  grp <- findInterval(x[ok], vec = thresholds, rightmost.closed = TRUE) + 1
  out[ok] <- if (higher_better) scores[grp] else rev(scores)[grp]
  
  out
}

cvh_thresholds <- list(
  DASH_score = make_percentile_thresholds(
    ukb_train_imputed$DASH_score,
    probs = c(0.25, 0.50, 0.75, 0.95)
  ),
  MET_total = make_percentile_thresholds(
    ukb_train_imputed$MET_total,
    probs = c(0.20, 0.40, 0.60, 0.80, 0.90)
  ),
  pack_year_index_pos = make_percentile_thresholds(
    ukb_train_imputed$pack_year_index[
      !is.na(ukb_train_imputed$pack_year_index) &
        ukb_train_imputed$pack_year_index > 0
    ],
    probs = c(0.25, 0.50, 0.75)
  )
)

calc_cvh_with_train_thresholds <- function(df, cvh_thresholds) {
  diet_score <- apply_percentile_score(
    x = df$DASH_score,
    thresholds = cvh_thresholds$DASH_score,
    scores = c(0, 25, 50, 80, 100),
    higher_better = TRUE
  )
  
  pa_score <- apply_percentile_score(
    x = df$MET_total,
    thresholds = cvh_thresholds$MET_total,
    scores = c(0, 20, 40, 60, 80, 100),
    higher_better = TRUE
  )
  
  nicotine_score <- rep(NA_real_, nrow(df))
  nicotine_score[!is.na(df$pack_year_index) & df$pack_year_index == 0] <- 100
  
  pos_idx <- !is.na(df$pack_year_index) & df$pack_year_index > 0
  nicotine_score[pos_idx] <- apply_percentile_score(
    x = df$pack_year_index[pos_idx],
    thresholds = cvh_thresholds$pack_year_index_pos,
    scores = c(75, 50, 25, 0),
    higher_better = TRUE
  )
  
  bmi_score <- case_when(
    is.na(df$bmi) ~ NA_real_,
    df$bmi < 25 ~ 100,
    df$bmi < 30 ~ 70,
    df$bmi < 35 ~ 30,
    df$bmi < 40 ~ 15,
    df$bmi >= 40 ~ 0
  )
  
  non_hdl <- df$biochem_cholesterol - df$biochem_hdl
  
  lipid_score <- case_when(
    is.na(non_hdl) ~ NA_real_,
    non_hdl < 130 ~ 100,
    non_hdl < 160 ~ 60,
    non_hdl < 190 ~ 40,
    non_hdl < 220 ~ 20,
    non_hdl >= 220 ~ 0
  )
  
  glucose_score <- rep(NA_real_, nrow(df))
  
  has_hba1c <- !is.na(df$biochem_hba1c)
  glucose_score[has_hba1c] <- case_when(
    df$biochem_hba1c[has_hba1c] < 5.7 ~ 100,
    df$biochem_hba1c[has_hba1c] < 6.5 ~ 60,
    df$biochem_hba1c[has_hba1c] < 7.0 ~ 40,
    df$biochem_hba1c[has_hba1c] < 8.0 ~ 30,
    df$biochem_hba1c[has_hba1c] < 9.0 ~ 20,
    df$biochem_hba1c[has_hba1c] < 10.0 ~ 10,
    df$biochem_hba1c[has_hba1c] >= 10.0 ~ 0
  )
  
  use_glucose <- is.na(df$biochem_hba1c) & !is.na(df$biochem_glucose)
  glucose_score[use_glucose] <- case_when(
    df$biochem_glucose[use_glucose] < 100 ~ 100,
    df$biochem_glucose[use_glucose] < 126 ~ 60,
    df$biochem_glucose[use_glucose] >= 126 ~ 40
  )
  
  sbp_score <- case_when(
    is.na(df$systolic_bp) ~ NA_real_,
    df$systolic_bp < 120 ~ 100,
    df$systolic_bp < 130 ~ 75,
    df$systolic_bp < 140 ~ 50,
    df$systolic_bp < 160 ~ 25,
    df$systolic_bp >= 160 ~ 0
  )
  
  dbp_score <- case_when(
    is.na(df$diastolic_bp) ~ NA_real_,
    df$diastolic_bp < 80 ~ 100,
    df$diastolic_bp < 90 ~ 50,
    df$diastolic_bp < 100 ~ 25,
    df$diastolic_bp >= 100 ~ 0
  )
  
  bp_score <- ifelse(
    is.na(sbp_score) & is.na(dbp_score),
    NA_real_,
    pmin(sbp_score, dbp_score, na.rm = TRUE)
  )
  
  sleep_score <- case_when(
    is.na(df$sleep_duration) ~ NA_real_,
    df$sleep_duration < 4  ~ 0,
    df$sleep_duration < 5  ~ 20,
    df$sleep_duration < 6  ~ 40,
    df$sleep_duration < 7  ~ 70,
    df$sleep_duration < 9  ~ 100,
    df$sleep_duration >= 9 ~ 100
  )
  
  df$CVH_diet_score     <- diet_score
  df$CVH_pa_score       <- pa_score
  df$CVH_nicotine_score <- nicotine_score
  df$CVH_bmi_score      <- bmi_score
  df$CVH_lipid_score    <- lipid_score
  df$CVH_glucose_score  <- glucose_score
  df$CVH_bp_score       <- bp_score
  df$CVH_sleep_score    <- sleep_score
  
  df$CVH_score <- rowMeans(cbind(
    diet_score,
    pa_score,
    nicotine_score,
    bmi_score,
    lipid_score,
    glucose_score,
    bp_score,
    sleep_score
  ), na.rm = TRUE)
  
  df
}

# -------------------------------
# 20. TRAIN-based thresholds for BHS
# -------------------------------
bhs_thresholds <- list(
  biochem_hba1c = quantile(ukb_train_imputed$biochem_hba1c, 0.75, na.rm = TRUE),
  biochem_hdl = quantile(ukb_train_imputed$biochem_hdl, 0.25, na.rm = TRUE),
  biochem_ldl_direct = quantile(ukb_train_imputed$biochem_ldl_direct, 0.75, na.rm = TRUE),
  biochem_triglycerides = quantile(ukb_train_imputed$biochem_triglycerides, 0.75, na.rm = TRUE),
  systolic_bp = quantile(ukb_train_imputed$systolic_bp, 0.75, na.rm = TRUE),
  diastolic_bp = quantile(ukb_train_imputed$diastolic_bp, 0.75, na.rm = TRUE),
  cardiac_pulse_rate = quantile(ukb_train_imputed$cardiac_pulse_rate, 0.75, na.rm = TRUE),
  biochem_crp = quantile(ukb_train_imputed$biochem_crp, 0.75, na.rm = TRUE),
  igf1 = quantile(ukb_train_imputed$igf1, 0.25, na.rm = TRUE),
  alanine_aminotransferase = quantile(ukb_train_imputed$alanine_aminotransferase, 0.75, na.rm = TRUE),
  aspartate_aminotransferase = quantile(ukb_train_imputed$aspartate_aminotransferase, 0.75, na.rm = TRUE),
  gamma_glutamyltransferase = quantile(ukb_train_imputed$gamma_glutamyltransferase, 0.75, na.rm = TRUE),
  creatinine = quantile(ukb_train_imputed$creatinine, 0.75, na.rm = TRUE)
)

risk_high_apply <- function(x, threshold) {
  out <- rep(NA_real_, length(x))
  ok <- !is.na(x)
  out[ok] <- as.numeric(x[ok] >= threshold)
  out
}

risk_low_apply <- function(x, threshold) {
  out <- rep(NA_real_, length(x))
  ok <- !is.na(x)
  out[ok] <- as.numeric(x[ok] <= threshold)
  out
}

calc_bhs_with_train_thresholds <- function(df, bhs_thresholds) {
  metabolic <- rowMeans(cbind(
    risk_high_apply(df$biochem_hba1c, bhs_thresholds$biochem_hba1c),
    risk_low_apply(df$biochem_hdl, bhs_thresholds$biochem_hdl),
    risk_high_apply(df$biochem_ldl_direct, bhs_thresholds$biochem_ldl_direct),
    risk_high_apply(df$biochem_triglycerides, bhs_thresholds$biochem_triglycerides)
  ), na.rm = TRUE)
  
  cardio <- rowMeans(cbind(
    risk_high_apply(df$systolic_bp, bhs_thresholds$systolic_bp),
    risk_high_apply(df$diastolic_bp, bhs_thresholds$diastolic_bp),
    risk_high_apply(df$cardiac_pulse_rate, bhs_thresholds$cardiac_pulse_rate)
  ), na.rm = TRUE)
  
  immune <- rowMeans(cbind(
    risk_high_apply(df$biochem_crp, bhs_thresholds$biochem_crp),
    risk_low_apply(df$igf1, bhs_thresholds$igf1)
  ), na.rm = TRUE)
  
  liver <- rowMeans(cbind(
    risk_high_apply(df$alanine_aminotransferase, bhs_thresholds$alanine_aminotransferase),
    risk_high_apply(df$aspartate_aminotransferase, bhs_thresholds$aspartate_aminotransferase),
    risk_high_apply(df$gamma_glutamyltransferase, bhs_thresholds$gamma_glutamyltransferase)
  ), na.rm = TRUE)
  
  kidney <- risk_high_apply(df$creatinine, bhs_thresholds$creatinine)
  
  df$BHS_metabolic <- metabolic
  df$BHS_cardiovascular <- cardio
  df$BHS_immune <- immune
  df$BHS_liver <- liver
  df$BHS_kidney <- kidney
  
  df$BHS <- rowMeans(cbind(
    metabolic,
    cardio,
    immune,
    liver,
    kidney
  ), na.rm = TRUE)
  
  df
}

# -------------------------------
# 21. Apply CVH / BHS
# -------------------------------
ukb_train_imputed <- calc_cvh_with_train_thresholds(ukb_train_imputed, cvh_thresholds)
ukb_val_imputed   <- calc_cvh_with_train_thresholds(ukb_val_imputed, cvh_thresholds)
ukb_test_imputed  <- calc_cvh_with_train_thresholds(ukb_test_imputed, cvh_thresholds)

ukb_train_imputed <- calc_bhs_with_train_thresholds(ukb_train_imputed, bhs_thresholds)
ukb_val_imputed   <- calc_bhs_with_train_thresholds(ukb_val_imputed, bhs_thresholds)
ukb_test_imputed  <- calc_bhs_with_train_thresholds(ukb_test_imputed, bhs_thresholds)

ukb_imputed_all <- bind_rows(
  ukb_train_imputed,
  ukb_val_imputed,
  ukb_test_imputed
)

# -------------------------------
# 22. Final score checks
# -------------------------------
cat("\nCVH score summary:\n")
print(summary(ukb_imputed_all$CVH_score))

cat("\nBHS summary:\n")
print(summary(ukb_imputed_all$BHS))

cat("\nCVH score missing count:\n")
print(sum(is.na(ukb_imputed_all$CVH_score)))

cat("\nBHS missing count:\n")
print(sum(is.na(ukb_imputed_all$BHS)))

# -------------------------------
# 23. Save outputs
# -------------------------------
remove_col_safe <- function(df, col_names) {
  cols_to_remove <- intersect(col_names, names(df))
  if (length(cols_to_remove) > 0) {
    df <- df[, !names(df) %in% cols_to_remove, drop = FALSE]
  }
  df
}

output_dir <- "../outputs"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

ukb_train_imputed <- remove_col_safe(ukb_train_imputed, c("data_type", "eid"))
ukb_val_imputed   <- remove_col_safe(ukb_val_imputed,   c("data_type", "eid"))
ukb_test_imputed  <- remove_col_safe(ukb_test_imputed,  c("data_type", "eid"))
ukb_imputed_all   <- remove_col_safe(ukb_imputed_all,   c("data_type", "eid"))

cat("Column removal completed.\n")
cat("Saving datasets...\n")

saveRDS(ukb_train_imputed, file.path(output_dir, "ukb_train_imputed.rds"))
saveRDS(ukb_val_imputed,   file.path(output_dir, "ukb_val_imputed.rds"))
saveRDS(ukb_test_imputed,  file.path(output_dir, "ukb_test_imputed.rds"))
saveRDS(ukb_imputed_all,   file.path(output_dir, "ukb_imputed_all.rds"))

fwrite(ukb_train_imputed, file.path(output_dir, "ukb_train_imputed.csv"))
fwrite(ukb_val_imputed,   file.path(output_dir, "ukb_val_imputed.csv"))
fwrite(ukb_test_imputed,  file.path(output_dir, "ukb_test_imputed.csv"))
fwrite(ukb_imputed_all,   file.path(output_dir, "ukb_imputed_all.csv"))

cat("Files saved successfully\n")

cat("Train has NA:", anyNA(ukb_train_imputed), "\n")
cat("Val has NA:", anyNA(ukb_val_imputed), "\n")
cat("Test has NA:", anyNA(ukb_test_imputed), "\n")
cat("Combined has NA:", anyNA(ukb_imputed_all), "\n")