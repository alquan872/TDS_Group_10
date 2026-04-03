# Q1.1 FINAL LASSO - TWO MODELS
# Model 1: All variables
# Model 2: Excluding age and systolic BP (sensitivity analysis) + adding them back for prediction

if (!interactive()) {
  setwd(dirname(normalizePath(commandArgs(trailingOnly=FALSE)[grep("--file=",commandArgs(trailingOnly=FALSE))][1] |> sub("--file=","",x=_))))
}
if (interactive()) {
  setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
}

DATA_DIR  <- "../../3_Correlation/outputs"

PLOT_DIR  <- "../outputs/plots"
TABLE_DIR <- "../outputs/tables"
MODEL_DIR <- "../outputs/models"
LOG_DIR   <- "../outputs/logs"

for (d in c(PLOT_DIR, TABLE_DIR, MODEL_DIR, LOG_DIR)) {
  if (dir.exists(d)) unlink(d, recursive = TRUE)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

TRAIN_PATH <- file.path(DATA_DIR, "ukb_train_drop_correlation_score.rds")
VAL_PATH   <- file.path(DATA_DIR, "ukb_val_drop_correlation_score.rds")
TEST_PATH  <- file.path(DATA_DIR, "ukb_test_drop_correlation_score.rds")

AGE_SYSBP_VARS <- c("systolic_bp", "age_at_recruitment")

suppressPackageStartupMessages({
  library(glmnet)
  library(igraph)
  library(pheatmap)
  library(sharp)
  library(fake)
  library(pROC)
})

cat("glmnet version:", as.character(packageVersion("glmnet")), "\n")
cat("sharp version: ", as.character(packageVersion("sharp")),  "\n")

save_plot <- function(filename_base, width, height, res, expr) {
  png(file.path(PLOT_DIR, paste0(filename_base, ".png")),
      width = width, height = height, res = res)
  expr
  dev.off()
  pdf(file.path(PLOT_DIR, paste0(filename_base, ".pdf")),
      width = width / res, height = height / res)
  expr
  dev.off()
  cat("  [plot saved]", filename_base, ".png/.pdf\n")
}

save_table <- function(df, filename) {
  write.csv(df, file.path(TABLE_DIR, filename), row.names = FALSE)
  cat("  [table saved]", filename, "\n")
}

save_model <- function(obj, filename) {
  saveRDS(obj, file.path(MODEL_DIR, filename))
  cat("  [model saved]", filename, "\n")
}

build_matrix <- function(data, outcome_var = "cvd") {
  x <- model.matrix(as.formula(paste(outcome_var, "~ .")), data = data)[, -1, drop = FALSE]
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

clean_varnames <- function(x) {
  x <- gsub("ses_employment_status", "employment_", x)
  x <- gsub("mh_psychiatric_care_history_", "psych_",   x)
  x <- gsub("cancer_behaviour",             "cancer_beh", x)
  x
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
    data.frame(predictor            = names(stab$selprop),
               selection_proportion = as.numeric(stab$selprop)),
    paste0("all_selection_proportions_", label, ".csv")
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
  
  clean_names <- clean_varnames(names(selprop_keep_local))
  
  # stable predictors bar plot
  for (ext in c("png", "pdf")) {
    if (ext == "png") {
      png(file.path(PLOT_DIR, paste0("stable_predictors_", label, ".png")),
          width = 3600, height = 2200, res = 220)
    } else {
      pdf(file.path(PLOT_DIR, paste0("stable_predictors_", label, ".pdf")),
          width = 3600/220, height = 2200/220)
    }
    par(mar = c(18, 6, 5, 3))
    plot(selprop_keep_local, type = "h", lwd = 5, las = 1,
         xlab = "", ylab = "Selection Proportion", xaxt = "n",
         ylim = c(min(pi_thresh_local - 0.05, min(selprop_keep_local) - 0.02), 1.02),
         col = "red", cex.lab = 1.4,
         main = paste("Stable Predictors -", label),
         cex.main = 1.5)
    abline(h = pi_thresh_local, lty = 2, col = "darkred", lwd = 2)
    text(x = 1, y = pi_thresh_local + 0.012,
         labels = paste0("pi = ", round(pi_thresh_local, 3)),
         pos = 4, col = "darkred", cex = 1.2, font = 2)
    text(x = 1, y = pi_thresh_local - 0.015,
         labels = paste0("lambda = ", round(lambda_best_local, 3)),
         pos = 4, col = "black", cex = 1.1)
    axis(side = 1, at = seq_along(selprop_keep_local),
         labels = clean_names,
         las = 2, cex.axis = 0.85, tick = TRUE)
    dev.off()
  }
  cat("  [plot saved]", paste0("stable_predictors_", label, ".png/.pdf"), "\n")
  
  # heatmap — skip if fewer than 3 stable predictors (pheatmap breaks fail)
  if (length(selprop_keep_local) >= 3) {
    clean_rownames <- clean_varnames(names(selprop_keep_local))
    heat_mat <- matrix(selprop_keep_local, ncol = 1,
                       dimnames = list(clean_rownames, "Selection Proportion"))
    n_rows   <- length(selprop_keep_local)
    h_height <- max(1800, n_rows * 180)
    
    png(file.path(PLOT_DIR, paste0("heatmap_", label, ".png")),
        width = 2200, height = h_height, res = 220)
    pheatmap(heat_mat,
             cluster_rows = TRUE, cluster_cols = FALSE, scale = "none",
             color        = colorRampPalette(c("white", "pink", "red", "darkred"))(100),
             main         = paste("Stability Selection Heatmap\n", label),
             fontsize_row = 10, fontsize_col = 11, fontsize = 11,
             border_color = "grey80", cellwidth = 120, cellheight = 35, angle_col = 0)
    dev.off()
    
    pdf(file.path(PLOT_DIR, paste0("heatmap_", label, ".pdf")),
        width = 2200/220, height = h_height/220)
    pheatmap(heat_mat,
             cluster_rows = TRUE, cluster_cols = FALSE, scale = "none",
             color        = colorRampPalette(c("white", "pink", "red", "darkred"))(100),
             main         = paste("Stability Selection Heatmap\n", label),
             fontsize_row = 10, fontsize_col = 11, fontsize = 11,
             border_color = "grey80", cellwidth = 120, cellheight = 35, angle_col = 0)
    dev.off()
    cat("  [plot saved]", paste0("heatmap_", label, ".png/.pdf"), "\n")
  } else {
    cat("  [heatmap skipped] fewer than 3 stable predictors\n")
  }
  
  # calibration plot
  for (ext in c("png", "pdf")) {
    if (ext == "png") {
      png(file.path(PLOT_DIR, paste0("calibration_plot_", label, ".png")),
          width = 2200, height = 1800, res = 220)
    } else {
      pdf(file.path(PLOT_DIR, paste0("calibration_plot_", label, ".pdf")),
          width = 2200/220, height = 1800/220)
    }
    CalibrationPlot(stab$out)
    dev.off()
  }
  cat("  [plot saved]", paste0("calibration_plot_", label, ".png/.pdf"), "\n")
  
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
         main = paste("ROC Validation -", label, "| AUC =", round(eval_res$auc_val, 3)))
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
         main = paste("ROC Test -", label, "| AUC =", round(eval_res$auc_test, 3)))
    dev.off()
  }
  cat("  [plot saved]", paste0("roc_test_", label, ".png/.pdf"), "\n")
}

# DATA
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

y_train <- train$cvd
y_val   <- val$cvd
y_test  <- test$cvd

# MODEL 1: ALL VARIABLES

x_train_m1 <- build_matrix(train)
x_val_m1   <- build_matrix(val)
x_test_m1  <- build_matrix(test)

stab_m1 <- run_stability_selection(x_train_m1, y_train, label = "model1_all_vars")

eval_m1 <- evaluate_model(
  x_train_m1, y_train,
  x_val_m1,   y_val,
  x_test_m1,  y_test,
  selected_vars = names(stab_m1$selprop_keep)
)

save_all_outputs(stab_m1, eval_m1, y_val, y_test, label = "model1_all_vars")

# MODEL 2: WITHOUT AGE/SYSBP

remove_age_sysbp <- function(data) {
  cols_remove <- which(colnames(data) %in% AGE_SYSBP_VARS)
  if (length(cols_remove) > 0) {
    cat("  Columns removed for stability selection:",
        paste(colnames(data)[cols_remove], collapse = ", "), "\n")
    data[, -cols_remove, drop = FALSE]
  } else {
    cat("  No age/sysBP columns found\n")
    data
  }
}

train_m2 <- remove_age_sysbp(train)
val_m2   <- remove_age_sysbp(val)
test_m2  <- remove_age_sysbp(test)

x_train_m2 <- build_matrix(train_m2)
x_val_m2   <- build_matrix(val_m2)
x_test_m2  <- build_matrix(test_m2)

stab_m2 <- run_stability_selection(x_train_m2, y_train, label = "model2_no_age_sysbp")

cat("\n  Adding age and systolic BP back for prediction...\n")

age_sysbp_cols <- colnames(x_train_m1)[colnames(x_train_m1) %in% AGE_SYSBP_VARS]
cat("  Columns added back:", paste(age_sysbp_cols, collapse = ", "), "\n")

selected_vars_m2_extended <- c(names(stab_m2$selprop_keep), age_sysbp_cols)
cat("  Total predictors for prediction:", length(selected_vars_m2_extended), "\n")

eval_m2 <- evaluate_model(
  x_train_m1, y_train,
  x_val_m1,   y_val,
  x_test_m1,  y_test,
  selected_vars = selected_vars_m2_extended
)

save_all_outputs(stab_m2, eval_m2, y_val, y_test, label = "model2_no_age_sysbp")

# Compare
comparison <- data.frame(
  model                 = c("Model1_AllVars", "Model2_NoAgeSysBP_SelectionOnly"),
  n_stable_predictors   = c(length(stab_m1$selprop_keep), length(stab_m2$selprop_keep)),
  n_predictors_in_model = c(length(names(stab_m1$selprop_keep)),
                            length(selected_vars_m2_extended)),
  pi_threshold          = c(stab_m1$pi_thresh,  stab_m2$pi_thresh),
  auc_validation        = c(eval_m1$auc_val,    eval_m2$auc_val),
  auc_test              = c(eval_m1$auc_test,   eval_m2$auc_test)
)

print(comparison)
save_table(comparison, "model_comparison.csv")

sink(file.path(TABLE_DIR, "session_info.txt"))
sessionInfo()
sink()

save(stab_m1, stab_m2, eval_m1, eval_m2, comparison,
     selected_vars_m2_extended,
     file = file.path(MODEL_DIR, "lasso_workspace.RData"))

all_files <- list.files("../outputs", recursive = TRUE, full.names = TRUE)
writeLines(all_files, file.path(TABLE_DIR, "saved_files_manifest.txt"))

cat("Number of files:", length(all_files), "\n")