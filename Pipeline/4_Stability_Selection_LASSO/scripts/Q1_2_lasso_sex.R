# Q1.2 SEX-STRATIFIED STABILITY SELECTION LASSO
# Model 1: All variables (stratified by sex)
# Model 2: Excluding age and systolic BP + adding them back for prediction (stratified by sex)

if (!interactive()) {
  setwd(dirname(normalizePath(commandArgs(trailingOnly=FALSE)[grep("--file=",commandArgs(trailingOnly=FALSE))][1] |> sub("--file=","",x=_))))
}
if (interactive()) {
  setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
}

DATA_DIR  <- "../../3_Correlation/outputs"

PLOT_DIR  <- "../outputs/plots_sex"
TABLE_DIR <- "../outputs/tables_sex"
MODEL_DIR <- "../outputs/models_sex"
LOG_DIR   <- "../outputs/logs_sex"

for (d in c(PLOT_DIR, TABLE_DIR, MODEL_DIR, LOG_DIR)) {
  if (dir.exists(d)) unlink(d, recursive = TRUE)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

TRAIN_PATH <- file.path(DATA_DIR, "ukb_train_drop_correlation_score.rds")
VAL_PATH   <- file.path(DATA_DIR, "ukb_val_drop_correlation_score.rds")
TEST_PATH  <- file.path(DATA_DIR, "ukb_test_drop_correlation_score.rds")


# Remove columns
AGE_SYSBP_VARS <- c("systolic_bp", "age_at_recruitment")


# Libraries

suppressPackageStartupMessages({
  library(glmnet)
  library(igraph)
  library(fake)
  library(sharp)
  library(pROC)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
})

cat("glmnet version:", as.character(packageVersion("glmnet")), "\n")
cat("sharp version: ", as.character(packageVersion("sharp")),  "\n")


# Define functions

save_table <- function(df, filename) {
  write.csv(df, file.path(TABLE_DIR, filename), row.names = FALSE)
  cat("  [table saved]", filename, "\n")
}

save_model <- function(obj, filename) {
  saveRDS(obj, file.path(MODEL_DIR, filename))
  cat("  [model saved]", filename, "\n")
}

clean_varnames <- function(x) {
  x <- gsub("ses_employment_status", "employment_", x)
  x <- gsub("mh_psychiatric_care_history_", "psych_",   x)
  x <- gsub("cancer_behaviour",             "cancer_beh", x)
  x
}

build_matrix <- function(data, outcome_var = "cvd") {
  x <- model.matrix(as.formula(paste(outcome_var, "~ . - sex")), data = data)[, -1, drop = FALSE]
  zero_var <- apply(x, 2, function(z) sd(z) == 0)
  cat("  Zero-variance columns removed:", sum(zero_var), "\n")
  x[, !zero_var, drop = FALSE]
}

align_matrix <- function(x_new, x_ref) {
  missing_cols <- setdiff(colnames(x_ref), colnames(x_new))
  if (length(missing_cols) > 0) {
    filler <- matrix(0, nrow = nrow(x_new), ncol = length(missing_cols),
                     dimnames = list(NULL, missing_cols))
    x_new <- cbind(x_new, filler)
  }
  x_new[, colnames(x_ref), drop = FALSE]
}

run_stability_selection <- function(x, y, label) {
  cat("\n── Stability Selection:", label, "──\n")
  set.seed(123)
  out <- VariableSelection(
    xdata   = x,
    ydata   = y,
    verbose = FALSE,
    family  = "binomial",
    n_cat   = 3,
    pi_list = seq(0.5, 0.9, by = 0.05)
  )
  hat_params   <- Argmax(out)
  pi_thresh    <- hat_params[1, "pi"]
  lambda_best  <- hat_params[1, "lambda"]
  selprop      <- SelectionProportions(out)
  selprop_keep <- sort(selprop[selprop >= pi_thresh], decreasing = TRUE)
  cat("  Calibrated pi:    ", pi_thresh,   "\n")
  cat("  Calibrated lambda:", lambda_best, "\n")
  cat("  Stable predictors:", length(selprop_keep), "\n")
  print(selprop_keep)
  list(out = out, hat_params = hat_params, pi_thresh = pi_thresh,
       lambda_best = lambda_best, selprop = selprop, selprop_keep = selprop_keep)
}

evaluate_model <- function(x_train, y_train, x_val, y_val, x_test, y_test, selected_vars) {
  x_tr  <- x_train[, selected_vars, drop = FALSE]
  x_v   <- align_matrix(x_val,  x_tr)[, selected_vars, drop = FALSE]
  x_te  <- align_matrix(x_test, x_tr)[, selected_vars, drop = FALSE]
  cvfit <- cv.glmnet(x_tr, y_train, family = "binomial", alpha = 1, type.measure = "auc")
  prob_val  <- as.vector(predict(cvfit, newx = x_v,  s = "lambda.min", type = "response"))
  prob_test <- as.vector(predict(cvfit, newx = x_te, s = "lambda.min", type = "response"))
  roc_val   <- roc(y_val,  prob_val,  quiet = TRUE)
  roc_test  <- roc(y_test, prob_test, quiet = TRUE)
  auc_val   <- as.numeric(auc(roc_val))
  auc_test  <- as.numeric(auc(roc_test))
  cat("  Validation AUC:", round(auc_val,  3), "\n")
  cat("  Test AUC:      ", round(auc_test, 3), "\n")
  list(cvfit = cvfit, roc_val = roc_val, roc_test = roc_test,
       auc_val = auc_val, auc_test = auc_test,
       prob_val = prob_val, prob_test = prob_test)
}

save_all_outputs <- function(stab, eval_res, y_val, y_test, label) {
  
  selprop_keep_local <- stab$selprop_keep
  pi_thresh_local    <- stab$pi_thresh
  lambda_best_local  <- stab$lambda_best
  
  # models
  save_model(stab$out,          paste0("sharp_",    label, ".rds"))
  save_model(stab$selprop,      paste0("selprop_",  label, ".rds"))
  save_model(eval_res$cvfit,    paste0("cvfit_",    label, ".rds"))
  save_model(eval_res$roc_test, paste0("roc_test_", label, ".rds"))
  
  # tables
  save_table(
    data.frame(lambda = stab$lambda_best, pi = stab$pi_thresh),
    paste0("calibrated_parameters_", label, ".csv")
  )
  save_table(
    data.frame(predictor            = names(selprop_keep_local),
               selection_proportion = as.numeric(selprop_keep_local)),
    paste0("stable_predictors_", label, ".csv")
  )
  save_table(
    data.frame(model               = label,
               n_stable_predictors = length(selprop_keep_local),
               pi_threshold        = pi_thresh_local,
               auc_validation      = round(eval_res$auc_val,  3),
               auc_test            = round(eval_res$auc_test, 3)),
    paste0("auc_results_", label, ".csv")
  )
  save_table(
    data.frame(observed              = y_test,
               predicted_probability = eval_res$prob_test),
    paste0("test_predictions_", label, ".csv")
  )
  
  # roc validation
  for (ext in c("png", "pdf")) {
    if (ext == "png") {
      png(file.path(PLOT_DIR, paste0("roc_validation_", label, ".png")),
          width = 1800, height = 1600, res = 220)
    } else {
      pdf(file.path(PLOT_DIR, paste0("roc_validation_", label, ".pdf")),
          width = 1800/220, height = 1600/220)
    }
    plot(eval_res$roc_val,
         main = paste("ROC Validation -", label,
                      "| AUC =", round(eval_res$auc_val, 3)))
    dev.off()
  }
  cat("  [plot saved]", paste0("roc_validation_", label, ".png/.pdf"), "\n")
  
  # roc test
  for (ext in c("png", "pdf")) {
    if (ext == "png") {
      png(file.path(PLOT_DIR, paste0("roc_test_", label, ".png")),
          width = 1800, height = 1600, res = 220)
    } else {
      pdf(file.path(PLOT_DIR, paste0("roc_test_", label, ".pdf")),
          width = 1800/220, height = 1600/220)
    }
    plot(eval_res$roc_test,
         main = paste("ROC Test -", label,
                      "| AUC =", round(eval_res$auc_test, 3)))
    dev.off()
  }
  cat("  [plot saved]", paste0("roc_test_", label, ".png/.pdf"), "\n")
}

save_sex_comparison_plot <- function(stab_m, stab_w, label) {
  
  pi_m   <- stab_m$pi_thresh
  pi_w   <- stab_w$pi_thresh
  sel_m  <- stab_m$selprop
  sel_w  <- stab_w$selprop
  
  all_preds  <- union(names(sel_m), names(sel_w))
  men_vals   <- sel_m[match(all_preds, names(sel_m))];   men_vals[is.na(men_vals)]   <- 0
  women_vals <- sel_w[match(all_preds, names(sel_w))]; women_vals[is.na(women_vals)] <- 0
  
  sel_df_full <- data.frame(
    predictor = all_preds,
    men       = as.numeric(men_vals),
    women     = as.numeric(women_vals)
  )
  
  param_df <- data.frame(
    sex    = c("men", "women"),
    pi     = c(pi_m, pi_w),
    lambda = c(stab_m$lambda_best, stab_w$lambda_best)
  )
  param_df$label <- paste0("pi = ",     round(param_df$pi,     3),
                           "\nlambda = ", round(param_df$lambda, 3))
  
  # stable in at least one sex
  sel_df_any <- sel_df_full %>%
    mutate(mean_selection = (men + women) / 2,
           stable_any     = (men >= pi_m) | (women >= pi_w)) %>%
    filter(stable_any)
  
  save_table(sel_df_any, paste0("stable_predictors_any_sex_", label, ".csv"))
  
  sel_long_any           <- pivot_longer(sel_df_any, cols = c(men, women),
                                         names_to = "sex", values_to = "selection")
  pred_order_any         <- sel_df_any %>% arrange(mean_selection) %>% pull(predictor)
  sel_long_any$predictor <- factor(clean_varnames(as.character(sel_long_any$predictor)),
                                   levels = clean_varnames(pred_order_any))
  
  p_any <- ggplot(sel_long_any, aes(x = selection, y = predictor)) +
    geom_segment(aes(x = 0, xend = selection, yend = predictor),
                 colour = "darkgreen", linewidth = 0.7) +
    geom_point(size = 3, colour = "darkgreen") +
    geom_vline(data = param_df, aes(xintercept = pi),
               linetype = "dashed", colour = "red") +
    geom_text(data = param_df, aes(x = pi, y = Inf, label = label),
              inherit.aes = FALSE, vjust = 1.1, hjust = -0.05,
              size = 3.8, colour = "red") +
    facet_wrap(~ sex, ncol = 2) +
    labs(x = "Selection proportion", y = "Predictor",
         title = paste("Stable predictors in at least one sex -", label)) +
    coord_cartesian(clip = "off") +
    theme_minimal(base_size = 13) +
    theme(plot.margin = ggplot2::margin(10, 40, 10, 10),
          strip.text  = element_text(face = "bold"))
  
  ggsave(file.path(PLOT_DIR, paste0("stable_predictors_any_sex_", label, ".png")),
         plot = p_any, width = 12, height = 8, dpi = 300)
  ggsave(file.path(PLOT_DIR, paste0("stable_predictors_any_sex_", label, ".pdf")),
         plot = p_any, width = 12, height = 8)
  cat("  [plot saved]", paste0("stable_predictors_any_sex_", label, ".png/.pdf"), "\n")
  
  # stable in both sexes
  sel_df_both <- sel_df_full %>%
    mutate(mean_selection = (men + women) / 2) %>%
    filter((men >= pi_m) & (women >= pi_w))
  
  save_table(sel_df_both, paste0("stable_predictors_both_sexes_", label, ".csv"))
  
  if (nrow(sel_df_both) > 0) {
    sel_long_both           <- pivot_longer(sel_df_both, cols = c(men, women),
                                            names_to = "sex", values_to = "selection")
    pred_order_both         <- sel_df_both %>% arrange(mean_selection) %>% pull(predictor)
    sel_long_both$predictor <- factor(clean_varnames(as.character(sel_long_both$predictor)),
                                      levels = clean_varnames(pred_order_both))
    
    p_both <- ggplot(sel_long_both, aes(x = selection, y = predictor)) +
      geom_segment(aes(x = 0, xend = selection, yend = predictor),
                   colour = "darkgreen", linewidth = 0.7) +
      geom_point(size = 3, colour = "darkgreen") +
      geom_vline(data = param_df, aes(xintercept = pi),
                 linetype = "dashed", colour = "red") +
      geom_text(data = param_df, aes(x = pi, y = Inf, label = label),
                inherit.aes = FALSE, vjust = 1.1, hjust = -0.05,
                size = 3.8, colour = "red") +
      facet_wrap(~ sex, ncol = 2) +
      labs(x = "Selection proportion", y = "Predictor",
           title = paste("Stable predictors in both sexes -", label)) +
      coord_cartesian(clip = "off") +
      theme_minimal(base_size = 13) +
      theme(plot.margin = ggplot2::margin(10, 40, 10, 10),
            strip.text  = element_text(face = "bold"))
    
    ggsave(file.path(PLOT_DIR, paste0("stable_predictors_both_sexes_", label, ".png")),
           plot = p_both, width = 12, height = 8, dpi = 300)
    ggsave(file.path(PLOT_DIR, paste0("stable_predictors_both_sexes_", label, ".pdf")),
           plot = p_both, width = 12, height = 8)
    cat("  [plot saved]", paste0("stable_predictors_both_sexes_", label, ".png/.pdf"), "\n")
  } else {
    cat("  No predictors stable in both sexes for", label, "\n")
  }
  
  list(sel_df_full = sel_df_full, sel_df_any = sel_df_any, sel_df_both = sel_df_both)
}

save_combined_roc <- function(eval_m, eval_w, label, split = "test") {
  roc_m <- if (split == "test") eval_m$roc_test else eval_m$roc_val
  roc_w <- if (split == "test") eval_w$roc_test else eval_w$roc_val
  auc_m <- if (split == "test") eval_m$auc_test else eval_m$auc_val
  auc_w <- if (split == "test") eval_w$auc_test else eval_w$auc_val
  
  for (ext in c("png", "pdf")) {
    if (ext == "png") {
      png(file.path(PLOT_DIR, paste0("roc_combined_", split, "_", label, ".png")),
          width = 1800, height = 1600, res = 220)
    } else {
      pdf(file.path(PLOT_DIR, paste0("roc_combined_", split, "_", label, ".pdf")),
          width = 1800/220, height = 1600/220)
    }
    plot(NULL, xlim = c(1, 0), ylim = c(0, 1),
         xlab = "False Positive Rate", ylab = "True Positive Rate",
         main = paste("ROC Curves by Sex -", label, "-", split))
    abline(0, 1, lty = 2, col = "grey70")
    plot(roc_m, add = TRUE, col = "blue",     lwd = 2)
    plot(roc_w, add = TRUE, col = "deeppink", lwd = 2)
    legend("bottomright",
           legend = c(paste0("Men (AUC = ",   round(auc_m, 3), ")"),
                      paste0("Women (AUC = ", round(auc_w, 3), ")")),
           col = c("blue", "deeppink"), lwd = 2, cex = 0.9)
    dev.off()
  }
  cat("  [plot saved]", paste0("roc_combined_", split, "_", label, ".png/.pdf"), "\n")
}


# Data

cat("\nLoading data...\n")

train <- readRDS(TRAIN_PATH)
val   <- readRDS(VAL_PATH)
test  <- readRDS(TEST_PATH)

train <- train[complete.cases(train), ]
val   <- val[complete.cases(val), ]
test  <- test[complete.cases(test), ]

train$cvd <- as.numeric(train$cvd)
val$cvd   <- as.numeric(val$cvd)
test$cvd  <- as.numeric(test$cvd)

cat("Train rows:", nrow(train), "\n")
cat("Val rows:  ", nrow(val),   "\n")
cat("Test rows: ", nrow(test),  "\n")


# Split by sex

train_m <- train[train$sex == "Male",   ]
train_w <- train[train$sex == "Female", ]
val_m   <- val[val$sex     == "Male",   ]
val_w   <- val[val$sex     == "Female", ]
test_m  <- test[test$sex   == "Male",   ]
test_w  <- test[test$sex   == "Female", ]

save_table(
  data.frame(sex   = c("Male", "Female"),
             train = c(nrow(train_m), nrow(train_w)),
             val   = c(nrow(val_m),   nrow(val_w)),
             test  = c(nrow(test_m),  nrow(test_w))),
  "sex_split_counts.csv"
)

y_train_m <- train_m$cvd;  y_val_m <- val_m$cvd;  y_test_m <- test_m$cvd
y_train_w <- train_w$cvd;  y_val_w <- val_w$cvd;  y_test_w <- test_w$cvd


# MODEL 1: ALL VARIABLES
#Men

x_train_m1_men <- build_matrix(train_m)
x_val_m1_men   <- build_matrix(val_m)
x_test_m1_men  <- build_matrix(test_m)

stab_m1_men <- run_stability_selection(x_train_m1_men, y_train_m,
                                       label = "model1_all_vars_men")
eval_m1_men <- evaluate_model(x_train_m1_men, y_train_m,
                              x_val_m1_men,   y_val_m,
                              x_test_m1_men,  y_test_m,
                              selected_vars = names(stab_m1_men$selprop_keep))
save_all_outputs(stab_m1_men, eval_m1_men, y_val_m, y_test_m,
                 label = "model1_all_vars_men")


#Women

x_train_m1_women <- build_matrix(train_w)
x_val_m1_women   <- build_matrix(val_w)
x_test_m1_women  <- build_matrix(test_w)

stab_m1_women <- run_stability_selection(x_train_m1_women, y_train_w,
                                         label = "model1_all_vars_women")
eval_m1_women <- evaluate_model(x_train_m1_women, y_train_w,
                                x_val_m1_women,   y_val_w,
                                x_test_m1_women,  y_test_w,
                                selected_vars = names(stab_m1_women$selprop_keep))
save_all_outputs(stab_m1_women, eval_m1_women, y_val_w, y_test_w,
                 label = "model1_all_vars_women")

sex_comp_m1 <- save_sex_comparison_plot(stab_m1_men, stab_m1_women,
                                        label = "model1_all_vars")
save_combined_roc(eval_m1_men, eval_m1_women, label = "model1_all_vars", split = "test")
save_combined_roc(eval_m1_men, eval_m1_women, label = "model1_all_vars", split = "validation")


# MODEL 2: EXCLUDING AGE AND SYSTOLIC BP

remove_age_sysbp <- function(data) {
  cols_remove <- which(colnames(data) %in% AGE_SYSBP_VARS)
  if (length(cols_remove) > 0) {
    cat("  Columns removed:", paste(colnames(data)[cols_remove], collapse = ", "), "\n")
    data[, -cols_remove, drop = FALSE]
  } else {
    cat("  No age/sysBP columns found\n")
    data
  }
}

#Men

train_m2_men <- remove_age_sysbp(train_m)
val_m2_men   <- remove_age_sysbp(val_m)
test_m2_men  <- remove_age_sysbp(test_m)

x_train_m2_men <- build_matrix(train_m2_men)
x_val_m2_men   <- build_matrix(val_m2_men)
x_test_m2_men  <- build_matrix(test_m2_men)

stab_m2_men <- run_stability_selection(x_train_m2_men, y_train_m,
                                       label = "model2_no_age_sysbp_men")

age_sysbp_cols_men   <- colnames(x_train_m1_men)[colnames(x_train_m1_men) %in% AGE_SYSBP_VARS]
selected_vars_m2_men <- c(names(stab_m2_men$selprop_keep), age_sysbp_cols_men)
cat("  Total predictors for prediction (men):", length(selected_vars_m2_men), "\n")

eval_m2_men <- evaluate_model(x_train_m1_men, y_train_m,
                              x_val_m1_men,   y_val_m,
                              x_test_m1_men,  y_test_m,
                              selected_vars = selected_vars_m2_men)
save_all_outputs(stab_m2_men, eval_m2_men, y_val_m, y_test_m,
                 label = "model2_no_age_sysbp_men")


#Women

train_m2_women <- remove_age_sysbp(train_w)
val_m2_women   <- remove_age_sysbp(val_w)
test_m2_women  <- remove_age_sysbp(test_w)

x_train_m2_women <- build_matrix(train_m2_women)
x_val_m2_women   <- build_matrix(val_m2_women)
x_test_m2_women  <- build_matrix(test_m2_women)

stab_m2_women <- run_stability_selection(x_train_m2_women, y_train_w,
                                         label = "model2_no_age_sysbp_women")

age_sysbp_cols_women   <- colnames(x_train_m1_women)[colnames(x_train_m1_women) %in% AGE_SYSBP_VARS]
selected_vars_m2_women <- c(names(stab_m2_women$selprop_keep), age_sysbp_cols_women)
cat("  Total predictors for prediction (women):", length(selected_vars_m2_women), "\n")

eval_m2_women <- evaluate_model(x_train_m1_women, y_train_w,
                                x_val_m1_women,   y_val_w,
                                x_test_m1_women,  y_test_w,
                                selected_vars = selected_vars_m2_women)
save_all_outputs(stab_m2_women, eval_m2_women, y_val_w, y_test_w,
                 label = "model2_no_age_sysbp_women")

sex_comp_m2 <- save_sex_comparison_plot(stab_m2_men, stab_m2_women,
                                        label = "model2_no_age_sysbp")
save_combined_roc(eval_m2_men, eval_m2_women, label = "model2_no_age_sysbp", split = "test")
save_combined_roc(eval_m2_men, eval_m2_women, label = "model2_no_age_sysbp", split = "validation")


# COMPARISON

comparison <- data.frame(
  model                 = c("M1_AllVars_Men",     "M1_AllVars_Women",
                            "M2_NoAgeSysBP_Men",  "M2_NoAgeSysBP_Women"),
  n_stable_predictors   = c(length(stab_m1_men$selprop_keep),
                            length(stab_m1_women$selprop_keep),
                            length(stab_m2_men$selprop_keep),
                            length(stab_m2_women$selprop_keep)),
  n_predictors_in_model = c(length(names(stab_m1_men$selprop_keep)),
                            length(names(stab_m1_women$selprop_keep)),
                            length(selected_vars_m2_men),
                            length(selected_vars_m2_women)),
  pi_threshold          = c(stab_m1_men$pi_thresh,   stab_m1_women$pi_thresh,
                            stab_m2_men$pi_thresh,   stab_m2_women$pi_thresh),
  auc_validation        = c(eval_m1_men$auc_val,     eval_m1_women$auc_val,
                            eval_m2_men$auc_val,     eval_m2_women$auc_val),
  auc_test              = c(eval_m1_men$auc_test,    eval_m1_women$auc_test,
                            eval_m2_men$auc_test,    eval_m2_women$auc_test)
)

print(comparison)
save_table(comparison, "full_model_comparison.csv")


# Info from R

sink(file.path(TABLE_DIR, "session_info.txt"))
sessionInfo()
sink()

save(stab_m1_men, stab_m1_women, stab_m2_men, stab_m2_women,
     eval_m1_men, eval_m1_women, eval_m2_men, eval_m2_women,
     comparison,
     selected_vars_m2_men, selected_vars_m2_women,
     file = file.path(MODEL_DIR, "lasso_sex_stratified_workspace.RData"))

all_files <- list.files("../outputs", recursive = TRUE, full.names = TRUE)
writeLines(all_files, file.path(TABLE_DIR, "saved_files_manifest.txt"))


cat("Total files:", length(all_files), "\n")