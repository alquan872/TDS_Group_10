# Q1.3 AGE-STRATIFIED STABILITY SELECTION LASSO
# Model 1: All variables (stratified by age group)
# Model 2: Excluding systolic BP + adding it back for prediction (stratified by age group)
# Age groups: <50, 50-69, 70+

if (!interactive()) {
  setwd(dirname(normalizePath(commandArgs(trailingOnly=FALSE)[grep("--file=",commandArgs(trailingOnly=FALSE))][1] |> sub("--file=","",x=_))))
}

if (interactive()) {
  setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
}


DATA_DIR  <- "../../3_Correlation/outputs"

PLOT_DIR  <- "../outputs/plots_age"
TABLE_DIR <- "../outputs/tables_age"
MODEL_DIR <- "../outputs/models_age"
LOG_DIR   <- "../outputs/logs_age"

for (d in c(PLOT_DIR, TABLE_DIR, MODEL_DIR, LOG_DIR)) {
  if (dir.exists(d)) unlink(d, recursive = TRUE)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}



TRAIN_PATH <- file.path(DATA_DIR, "ukb_train_drop_correlation_score.rds")
VAL_PATH   <- file.path(DATA_DIR, "ukb_val_drop_correlation_score.rds")
TEST_PATH  <- file.path(DATA_DIR, "ukb_test_drop_correlation_score.rds")


# Remove
SYSBP_VAR     <- "systolic_bp"


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


# Create Function

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

clean_label <- function(x) gsub("[^A-Za-z0-9]+", "_", x)

build_matrix <- function(data, outcome_var = "cvd") {
  formula_str <- paste(outcome_var, "~ . - age_at_recruitment - age_group")
  x <- model.matrix(as.formula(formula_str), data = data)[, -1, drop = FALSE]
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
  
  if (length(selected_vars) < 2) {
    cat("  Skipping model - fewer than 2 predictors selected\n")
    return(list(cvfit = NULL, roc_val = NULL, roc_test = NULL,
                auc_val = NA, auc_test = NA,
                prob_val = NA, prob_test = NA))
  }
  
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
  save_model(stab$out,     paste0("sharp_",   label, ".rds"))
  save_model(stab$selprop, paste0("selprop_", label, ".rds"))
  
  # tables always
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
  
  # skip plots and predictions if model was not fitted
  if (is.null(eval_res$cvfit)) {
    cat("  Skipping plots and predictions for", label, "- model not fitted\n")
    return(invisible(NULL))
  }
  
  save_model(eval_res$cvfit,    paste0("cvfit_",    label, ".rds"))
  save_model(eval_res$roc_test, paste0("roc_test_", label, ".rds"))
  
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

save_age_comparison_plot <- function(stab_list, label, age_levels) {
  
  all_preds <- Reduce(union, lapply(stab_list, function(s) names(s$selprop)))
  age_cols  <- clean_label(age_levels)
  
  sel_df <- data.frame(predictor = all_preds)
  for (i in seq_along(age_levels)) {
    g    <- age_levels[i]
    vals <- stab_list[[g]]$selprop[match(all_preds, names(stab_list[[g]]$selprop))]
    vals[is.na(vals)] <- 0
    sel_df[[age_cols[i]]] <- as.numeric(vals)
  }
  
  param_df <- data.frame(
    age_group  = age_cols,
    pi         = sapply(stab_list, function(s) s$pi_thresh),
    lambda     = sapply(stab_list, function(s) s$lambda_best)
  )
  param_df$label_text <- paste0("pi = ",     round(param_df$pi,     3),
                                "\nlambda = ", round(param_df$lambda, 3))
  
  # stable in at least one age group
  stable_any <- Reduce("|", lapply(seq_along(age_levels), function(i) {
    sel_df[[age_cols[i]]] >= stab_list[[age_levels[i]]]$pi_thresh
  }))
  
  sel_df_any <- sel_df[stable_any, ]
  sel_df_any$mean_selection <- rowMeans(sel_df_any[, age_cols])
  
  save_table(sel_df_any, paste0("stable_predictors_any_age_", label, ".csv"))
  
  if (nrow(sel_df_any) > 0) {
    sel_long_any           <- pivot_longer(sel_df_any, cols = all_of(age_cols),
                                           names_to = "age_group", values_to = "selection")
    pred_order_any         <- sel_df_any[order(sel_df_any$mean_selection), "predictor"]
    sel_long_any$predictor <- factor(clean_varnames(sel_long_any$predictor),
                                     levels = clean_varnames(pred_order_any))
    sel_long_any$age_group <- factor(sel_long_any$age_group, levels = age_cols)
    
    p_any <- ggplot(sel_long_any, aes(x = selection, y = predictor)) +
      geom_segment(aes(x = 0, xend = selection, yend = predictor),
                   colour = "darkgreen", linewidth = 0.7) +
      geom_point(size = 3, colour = "darkgreen") +
      geom_vline(data = param_df, aes(xintercept = pi),
                 linetype = "dashed", colour = "red") +
      geom_text(data = param_df, aes(x = pi, y = Inf, label = label_text),
                inherit.aes = FALSE, vjust = 1.1, hjust = -0.05,
                size = 3.5, colour = "red") +
      facet_wrap(~ age_group, ncol = 3) +
      labs(x = "Selection proportion", y = "Predictor",
           title = paste("Stable predictors in at least one age group -", label)) +
      coord_cartesian(clip = "off") +
      theme_minimal(base_size = 13) +
      theme(plot.margin = ggplot2::margin(10, 40, 10, 10),
            strip.text  = element_text(face = "bold"))
    
    ggsave(file.path(PLOT_DIR, paste0("stable_predictors_any_age_", label, ".png")),
           plot = p_any, width = 14, height = 8, dpi = 300)
    ggsave(file.path(PLOT_DIR, paste0("stable_predictors_any_age_", label, ".pdf")),
           plot = p_any, width = 14, height = 8)
    cat("  [plot saved]", paste0("stable_predictors_any_age_", label, ".png/.pdf"), "\n")
  }
  
  # stable in all age groups
  stable_all <- Reduce("&", lapply(seq_along(age_levels), function(i) {
    sel_df[[age_cols[i]]] >= stab_list[[age_levels[i]]]$pi_thresh
  }))
  
  sel_df_all <- sel_df[stable_all, ]
  save_table(sel_df_all, paste0("stable_predictors_all_ages_", label, ".csv"))
  
  if (nrow(sel_df_all) > 0) {
    sel_df_all$mean_selection <- rowMeans(sel_df_all[, age_cols])
    sel_long_all              <- pivot_longer(sel_df_all, cols = all_of(age_cols),
                                              names_to = "age_group", values_to = "selection")
    pred_order_all            <- sel_df_all[order(sel_df_all$mean_selection), "predictor"]
    sel_long_all$predictor    <- factor(clean_varnames(sel_long_all$predictor),
                                        levels = clean_varnames(pred_order_all))
    sel_long_all$age_group    <- factor(sel_long_all$age_group, levels = age_cols)
    
    p_all <- ggplot(sel_long_all, aes(x = selection, y = predictor)) +
      geom_segment(aes(x = 0, xend = selection, yend = predictor),
                   colour = "darkgreen", linewidth = 0.7) +
      geom_point(size = 3, colour = "darkgreen") +
      geom_vline(data = param_df, aes(xintercept = pi),
                 linetype = "dashed", colour = "red") +
      geom_text(data = param_df, aes(x = pi, y = Inf, label = label_text),
                inherit.aes = FALSE, vjust = 1.1, hjust = -0.05,
                size = 3.5, colour = "red") +
      facet_wrap(~ age_group, ncol = 3) +
      labs(x = "Selection proportion", y = "Predictor",
           title = paste("Stable predictors in all age groups -", label)) +
      coord_cartesian(clip = "off") +
      theme_minimal(base_size = 13) +
      theme(plot.margin = ggplot2::margin(10, 40, 10, 10),
            strip.text  = element_text(face = "bold"))
    
    ggsave(file.path(PLOT_DIR, paste0("stable_predictors_all_ages_", label, ".png")),
           plot = p_all, width = 14, height = 8, dpi = 300)
    ggsave(file.path(PLOT_DIR, paste0("stable_predictors_all_ages_", label, ".pdf")),
           plot = p_all, width = 14, height = 8)
    cat("  [plot saved]", paste0("stable_predictors_all_ages_", label, ".png/.pdf"), "\n")
  } else {
    cat("  No predictors stable in all age groups for", label, "\n")
  }
}

save_combined_roc_age <- function(eval_list, label, age_levels, split = "test") {
  cols <- c("blue", "darkgreen", "red")
  
  valid_groups <- age_levels[sapply(age_levels, function(g) !is.null(eval_list[[g]]$cvfit))]
  
  if (length(valid_groups) == 0) {
    cat("  No valid models for combined ROC -", label, "\n")
    return(invisible(NULL))
  }
  
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
         main = paste("ROC Curves by Age Group -", label, "-", split))
    abline(0, 1, lty = 2, col = "grey70")
    
    legend_labels <- c()
    for (i in seq_along(valid_groups)) {
      g     <- valid_groups[i]
      roc_g <- if (split == "test") eval_list[[g]]$roc_test else eval_list[[g]]$roc_val
      auc_g <- if (split == "test") eval_list[[g]]$auc_test else eval_list[[g]]$auc_val
      plot(roc_g, add = TRUE, col = cols[i], lwd = 2)
      legend_labels <- c(legend_labels, paste0(g, " (AUC = ", round(auc_g, 3), ")"))
    }
    
    legend("bottomright", legend = legend_labels, col = cols[seq_along(valid_groups)],
           lwd = 2, cex = 0.9)
    dev.off()
  }
  cat("  [plot saved]", paste0("roc_combined_", split, "_", label, ".png/.pdf"), "\n")
}


# Read data

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


# Age groups

create_age_groups <- function(data) {
  data$age_group <- cut(
    data$age_at_recruitment,
    breaks = c(-Inf, 50, 70, Inf),
    labels = c("<50", "50-69", "70+"),
    right  = FALSE
  )
  data
}

train <- create_age_groups(train)
val   <- create_age_groups(val)
test  <- create_age_groups(test)

AGE_LEVELS <- c("<50", "50-69", "70+")

save_table(
  data.frame(age_group = AGE_LEVELS,
             train = sapply(AGE_LEVELS, function(g) sum(train$age_group == g)),
             val   = sapply(AGE_LEVELS, function(g) sum(val$age_group   == g)),
             test  = sapply(AGE_LEVELS, function(g) sum(test$age_group  == g))),
  "age_split_counts.csv"
)


# Age split

split_by_age <- function(data, g) data[data$age_group == g, ]

train_age <- lapply(AGE_LEVELS, function(g) split_by_age(train, g))
val_age   <- lapply(AGE_LEVELS, function(g) split_by_age(val,   g))
test_age  <- lapply(AGE_LEVELS, function(g) split_by_age(test,  g))
names(train_age) <- names(val_age) <- names(test_age) <- AGE_LEVELS

y_train_age <- lapply(train_age, function(d) d$cvd)
y_val_age   <- lapply(val_age,   function(d) d$cvd)
y_test_age  <- lapply(test_age,  function(d) d$cvd)


# MODEL 1: ALL VARIABLES - BY AGE GROUP

x_train_m1 <- lapply(AGE_LEVELS, function(g) build_matrix(train_age[[g]]))
x_val_m1   <- lapply(AGE_LEVELS, function(g) build_matrix(val_age[[g]]))
x_test_m1  <- lapply(AGE_LEVELS, function(g) build_matrix(test_age[[g]]))
names(x_train_m1) <- names(x_val_m1) <- names(x_test_m1) <- AGE_LEVELS

stab_m1 <- list()
eval_m1 <- list()

for (g in AGE_LEVELS) {
  cat("\n──", g, "──\n")
  lbl          <- paste0("model1_all_vars_age_", clean_label(g))
  stab_m1[[g]] <- run_stability_selection(x_train_m1[[g]], y_train_age[[g]], label = lbl)
  eval_m1[[g]] <- evaluate_model(x_train_m1[[g]], y_train_age[[g]],
                                 x_val_m1[[g]],   y_val_age[[g]],
                                 x_test_m1[[g]],  y_test_age[[g]],
                                 selected_vars = names(stab_m1[[g]]$selprop_keep))
  save_all_outputs(stab_m1[[g]], eval_m1[[g]], y_val_age[[g]], y_test_age[[g]], label = lbl)
}

save_age_comparison_plot(stab_m1, label = "model1_all_vars", age_levels = AGE_LEVELS)
save_combined_roc_age(eval_m1, label = "model1_all_vars", age_levels = AGE_LEVELS, split = "test")
save_combined_roc_age(eval_m1, label = "model1_all_vars", age_levels = AGE_LEVELS, split = "validation")


# MODEL 2: EXCLUDING SYSTOLIC BP + ADDING BACK FOR PREDICTION

remove_sysbp <- function(data) {
  cols_remove <- which(colnames(data) == SYSBP_VAR)
  if (length(cols_remove) > 0) {
    cat("  Column removed:", SYSBP_VAR, "\n")
    data[, -cols_remove, drop = FALSE]
  } else {
    cat("  systolic_bp not found\n")
    data
  }
}

train_m2_age <- lapply(train_age, remove_sysbp)
val_m2_age   <- lapply(val_age,   remove_sysbp)
test_m2_age  <- lapply(test_age,  remove_sysbp)

x_train_m2 <- lapply(AGE_LEVELS, function(g) build_matrix(train_m2_age[[g]]))
x_val_m2   <- lapply(AGE_LEVELS, function(g) build_matrix(val_m2_age[[g]]))
x_test_m2  <- lapply(AGE_LEVELS, function(g) build_matrix(test_m2_age[[g]]))
names(x_train_m2) <- names(x_val_m2) <- names(x_test_m2) <- AGE_LEVELS

stab_m2          <- list()
eval_m2          <- list()
selected_vars_m2 <- list()

for (g in AGE_LEVELS) {
  cat("\n──", g, "──\n")
  lbl          <- paste0("model2_no_sysbp_age_", clean_label(g))
  stab_m2[[g]] <- run_stability_selection(x_train_m2[[g]], y_train_age[[g]], label = lbl)
  
  sysbp_col             <- colnames(x_train_m1[[g]])[colnames(x_train_m1[[g]]) == SYSBP_VAR]
  selected_vars_m2[[g]] <- c(names(stab_m2[[g]]$selprop_keep), sysbp_col)
  cat("  Total predictors for prediction:", length(selected_vars_m2[[g]]), "\n")
  
  eval_m2[[g]] <- evaluate_model(x_train_m1[[g]], y_train_age[[g]],
                                 x_val_m1[[g]],   y_val_age[[g]],
                                 x_test_m1[[g]],  y_test_age[[g]],
                                 selected_vars = selected_vars_m2[[g]])
  save_all_outputs(stab_m2[[g]], eval_m2[[g]], y_val_age[[g]], y_test_age[[g]], label = lbl)
}

save_age_comparison_plot(stab_m2, label = "model2_no_sysbp", age_levels = AGE_LEVELS)
save_combined_roc_age(eval_m2, label = "model2_no_sysbp", age_levels = AGE_LEVELS, split = "test")
save_combined_roc_age(eval_m2, label = "model2_no_sysbp", age_levels = AGE_LEVELS, split = "validation")


# Comparison between models

comparison <- data.frame(
  model                 = c(paste0("M1_AllVars_",  AGE_LEVELS),
                            paste0("M2_NoSysBP_", AGE_LEVELS)),
  n_stable_predictors   = c(sapply(AGE_LEVELS, function(g) length(stab_m1[[g]]$selprop_keep)),
                            sapply(AGE_LEVELS, function(g) length(stab_m2[[g]]$selprop_keep))),
  n_predictors_in_model = c(sapply(AGE_LEVELS, function(g) length(names(stab_m1[[g]]$selprop_keep))),
                            sapply(AGE_LEVELS, function(g) length(selected_vars_m2[[g]]))),
  pi_threshold          = c(sapply(AGE_LEVELS, function(g) stab_m1[[g]]$pi_thresh),
                            sapply(AGE_LEVELS, function(g) stab_m2[[g]]$pi_thresh)),
  auc_validation        = c(sapply(AGE_LEVELS, function(g) eval_m1[[g]]$auc_val),
                            sapply(AGE_LEVELS, function(g) eval_m2[[g]]$auc_val)),
  auc_test              = c(sapply(AGE_LEVELS, function(g) eval_m1[[g]]$auc_test),
                            sapply(AGE_LEVELS, function(g) eval_m2[[g]]$auc_test))
)

print(comparison)
save_table(comparison, "full_model_comparison.csv")


# Save R info
sink(file.path(TABLE_DIR, "session_info.txt"))
sessionInfo()
sink()

save(stab_m1, stab_m2, eval_m1, eval_m2,
     comparison, selected_vars_m2,
     file = file.path(MODEL_DIR, "lasso_age_stratified_workspace.RData"))

all_files <- list.files("../outputs", recursive = TRUE, full.names = TRUE)
writeLines(all_files, file.path(TABLE_DIR, "saved_files_manifest.txt"))


cat("Total files:", length(all_files), "\n")