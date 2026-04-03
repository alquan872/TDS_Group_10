# Q1.4 RANDOM FOREST vs LASSO - AUC COMPARISON

if (!interactive()) {
  setwd(dirname(normalizePath(commandArgs(trailingOnly=FALSE)[grep("--file=",commandArgs(trailingOnly=FALSE))][1] |> sub("--file=","",x=_))))
}
if (interactive()) {
  setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
}



DATA_DIR  <- "../../3_Correlation/outputs"

PLOT_DIR  <- "../outputs/plots_rf"
TABLE_DIR <- "../outputs/tables_rf"
MODEL_DIR <- "../outputs/models_rf"
LOG_DIR   <- "../outputs/logs_rf"

for (d in c(PLOT_DIR, TABLE_DIR, MODEL_DIR, LOG_DIR)) {
  if (dir.exists(d)) unlink(d, recursive = TRUE)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}



TRAIN_PATH <- file.path(DATA_DIR, "ukb_train_drop_correlation_score.rds")
VAL_PATH   <- file.path(DATA_DIR, "ukb_val_drop_correlation_score.rds")
TEST_PATH  <- file.path(DATA_DIR, "ukb_test_drop_correlation_score.rds")


# Libraries
suppressPackageStartupMessages({
  library(glmnet)
  library(ranger)
  library(pROC)
  library(ggplot2)
  library(dplyr)
})

cat("glmnet version:", as.character(packageVersion("glmnet")), "\n")
cat("ranger version:", as.character(packageVersion("ranger")),  "\n")


# Functions
save_table <- function(df, filename) {
  write.csv(df, file.path(TABLE_DIR, filename), row.names = FALSE)
  cat("  [table saved]", filename, "\n")
}

save_model <- function(obj, filename) {
  saveRDS(obj, file.path(MODEL_DIR, filename))
  cat("  [model saved]", filename, "\n")
}

save_roc_plot <- function(roc_obj, auc_val, label, filename_base) {
  for (ext in c("png", "pdf")) {
    if (ext == "png") {
      png(file.path(PLOT_DIR, paste0(filename_base, ".png")),
          width = 1800, height = 1600, res = 220)
    } else {
      pdf(file.path(PLOT_DIR, paste0(filename_base, ".pdf")),
          width = 1800/220, height = 1600/220)
    }
    plot(roc_obj, main = paste(label, "| AUC =", round(auc_val, 3)))
    dev.off()
  }
  cat("  [plot saved]", paste0(filename_base, ".png/.pdf"), "\n")
}

clean_varnames <- function(x) {
  x <- gsub("ses_employment_status", "employment_", x)
  x <- gsub("mh_psychiatric_care_history_", "psych_",   x)
  x <- gsub("cancer_behaviour",             "cancer_beh", x)
  x
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

save_table(
  data.frame(split          = c("train", "val", "test"),
             n              = c(nrow(train), nrow(val), nrow(test)),
             cvd_prevalence = c(mean(train$cvd), mean(val$cvd), mean(test$cvd))),
  "data_split_summary.csv"
)


# LASSO

x_train <- model.matrix(cvd ~ ., data = train)[, -1]
x_val   <- model.matrix(cvd ~ ., data = val)[,   -1]
x_test  <- model.matrix(cvd ~ ., data = test)[,  -1]

x_train <- x_train[, apply(x_train, 2, sd) != 0]

y_train <- train$cvd
y_val   <- val$cvd
y_test  <- test$cvd

set.seed(123)
cvfit_lasso <- cv.glmnet(
  x_train, y_train,
  family       = "binomial",
  alpha        = 1,
  type.measure = "auc"
)

save_model(cvfit_lasso, "lasso_cvfit.rds")

x_val_aligned  <- align_matrix(x_val,  x_train)
x_test_aligned <- align_matrix(x_test, x_train)

prob_lasso_val  <- as.vector(predict(cvfit_lasso, newx = x_val_aligned,  s = "lambda.min", type = "response"))
prob_lasso_test <- as.vector(predict(cvfit_lasso, newx = x_test_aligned, s = "lambda.min", type = "response"))

roc_lasso_val  <- roc(y_val,  prob_lasso_val,  quiet = TRUE)
roc_lasso_test <- roc(y_test, prob_lasso_test, quiet = TRUE)

auc_lasso_val  <- as.numeric(auc(roc_lasso_val))
auc_lasso_test <- as.numeric(auc(roc_lasso_test))

cat("  LASSO Validation AUC:", round(auc_lasso_val,  3), "\n")
cat("  LASSO Test AUC:      ", round(auc_lasso_test, 3), "\n")

save_model(roc_lasso_test, "lasso_roc_test.rds")

save_table(
  data.frame(observed              = y_test,
             predicted_probability = prob_lasso_test),
  "lasso_test_predictions.csv"
)

save_table(
  data.frame(model          = "LASSO",
             auc_validation = round(auc_lasso_val,  3),
             auc_test       = round(auc_lasso_test, 3)),
  "lasso_auc.csv"
)

save_roc_plot(roc_lasso_val,  auc_lasso_val,  "LASSO Validation", "roc_lasso_validation")
save_roc_plot(roc_lasso_test, auc_lasso_test, "LASSO Test",       "roc_lasso_test")


# RANDOM FOREST

train_rf     <- train
val_rf       <- val
test_rf      <- test
train_rf$cvd <- as.factor(train_rf$cvd)
val_rf$cvd   <- as.factor(val_rf$cvd)
test_rf$cvd  <- as.factor(test_rf$cvd)

set.seed(123)
rf_model <- ranger(
  cvd ~ .,
  data        = train_rf,
  num.trees   = 500,
  probability = TRUE,
  importance  = "permutation"
)

save_model(rf_model, "rf_model.rds")

# variable importance table
vi_df <- data.frame(
  variable   = names(rf_model$variable.importance),
  importance = as.numeric(rf_model$variable.importance)
) %>% arrange(desc(importance))

save_table(vi_df, "rf_variable_importance.csv")

# variable importance plot - top 20
vi_top20          <- head(vi_df, 20)
vi_top20$variable <- clean_varnames(vi_top20$variable)
vi_top20$variable <- factor(vi_top20$variable, levels = rev(vi_top20$variable))

p_vi <- ggplot(vi_top20, aes(x = importance, y = variable)) +
  geom_segment(aes(x = 0, xend = importance, yend = variable),
               colour = "steelblue", linewidth = 0.7) +
  geom_point(size = 3, colour = "steelblue") +
  labs(x     = "Permutation importance",
       y     = "Predictor",
       title = "Top 20 predictors from ranger random forest: Which variables are depended on the most for prediction?") +
  theme_minimal(base_size = 12) +
  theme(plot.title  = element_text(size = 10, face = "bold"),
        axis.text.y = element_text(size = 9))

ggsave(file.path(PLOT_DIR, "rf_variable_importance_top20.png"),
       plot = p_vi, width = 12, height = 8, dpi = 300)
ggsave(file.path(PLOT_DIR, "rf_variable_importance_top20.pdf"),
       plot = p_vi, width = 12, height = 8)
cat("  [plot saved] rf_variable_importance_top20.png/.pdf\n")

# predictions
prob_rf_val  <- predict(rf_model, data = val_rf)$predictions[, "1"]
prob_rf_test <- predict(rf_model, data = test_rf)$predictions[, "1"]

roc_rf_val  <- roc(val_rf$cvd,  prob_rf_val,  quiet = TRUE)
roc_rf_test <- roc(test_rf$cvd, prob_rf_test, quiet = TRUE)

auc_rf_val  <- as.numeric(auc(roc_rf_val))
auc_rf_test <- as.numeric(auc(roc_rf_test))

cat("  RF Validation AUC:", round(auc_rf_val,  3), "\n")
cat("  RF Test AUC:      ", round(auc_rf_test, 3), "\n")

save_model(roc_rf_test, "rf_roc_test.rds")

save_table(
  data.frame(observed              = as.numeric(as.character(test_rf$cvd)),
             predicted_probability = prob_rf_test),
  "rf_test_predictions.csv"
)

save_table(
  data.frame(model          = "Random Forest",
             auc_validation = round(auc_rf_val,  3),
             auc_test       = round(auc_rf_test, 3)),
  "rf_auc.csv"
)

save_roc_plot(roc_rf_val,  auc_rf_val,  "Random Forest Validation", "roc_rf_validation")
save_roc_plot(roc_rf_test, auc_rf_test, "Random Forest Test",       "roc_rf_test")


# Comparison between models

comparison <- data.frame(
  model          = c("LASSO", "Random Forest"),
  auc_validation = c(auc_lasso_val,  auc_rf_val),
  auc_test       = c(auc_lasso_test, auc_rf_test)
)

print(comparison)
save_table(comparison, "auc_comparison.csv")

# combined ROC - validation
for (ext in c("png", "pdf")) {
  if (ext == "png") {
    png(file.path(PLOT_DIR, "roc_combined_validation.png"), width = 1800, height = 1600, res = 220)
  } else {
    pdf(file.path(PLOT_DIR, "roc_combined_validation.pdf"), width = 1800/220, height = 1600/220)
  }
  plot(roc_lasso_val, col = "red",  lwd = 2,
       main = "ROC Curves - Validation: LASSO vs Random Forest")
  plot(roc_rf_val,    col = "blue", lwd = 2, add = TRUE)
  abline(0, 1, lty = 2, col = "grey70")
  legend("bottomright",
         legend = c(paste("LASSO (AUC =", round(auc_lasso_val, 3), ")"),
                    paste("RF (AUC =",    round(auc_rf_val,    3), ")")),
         col = c("red", "blue"), lwd = 2, cex = 0.9)
  dev.off()
}
cat("  [plot saved] roc_combined_validation.png/.pdf\n")

# combined ROC - test
for (ext in c("png", "pdf")) {
  if (ext == "png") {
    png(file.path(PLOT_DIR, "roc_combined_test.png"), width = 1800, height = 1600, res = 220)
  } else {
    pdf(file.path(PLOT_DIR, "roc_combined_test.pdf"), width = 1800/220, height = 1600/220)
  }
  plot(roc_lasso_test, col = "red",  lwd = 2,
       main = "ROC Curves - Test: LASSO vs Random Forest")
  plot(roc_rf_test,    col = "blue", lwd = 2, add = TRUE)
  abline(0, 1, lty = 2, col = "grey70")
  legend("bottomright",
         legend = c(paste("LASSO (AUC =", round(auc_lasso_test, 3), ")"),
                    paste("RF (AUC =",    round(auc_rf_test,    3), ")")),
         col = c("red", "blue"), lwd = 2, cex = 0.9)
  dev.off()
}
cat("  [plot saved] roc_combined_test.png/.pdf\n")


# R info

sink(file.path(TABLE_DIR, "session_info.txt"))
sessionInfo()
sink()

save(cvfit_lasso, rf_model, roc_lasso_test, roc_rf_test,
     comparison, vi_df,
     file = file.path(MODEL_DIR, "rf_lasso_workspace.RData"))

all_files <- list.files("../outputs", recursive = TRUE, full.names = TRUE)
writeLines(all_files, file.path(TABLE_DIR, "saved_files_manifest.txt"))


cat("Total files:", length(all_files), "\n")