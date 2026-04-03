if (sys.nframe() == 0 && !interactive()) {
  this_file <- normalizePath(sub("--file=", "", 
                                 commandArgs(trailingOnly = FALSE)[grep("--file=", commandArgs(trailingOnly = FALSE))][1]
  ))
  setwd(dirname(this_file))
}
if (interactive()) {
  setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
}

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(knitr)
  library(kableExtra)
  library(parallel)
  library(ranger)
  library(pROC)
  library(ggrepel)
})

# directories
DATA_DIR  <- "../../3_Correlation/outputs"
PLOT_DIR  <- "../outputs/plots"
TABLE_DIR <- "../outputs/tables"
MODEL_DIR <- "../outputs/models"
LOG_DIR   <- "../outputs/logs"

for (d in c(PLOT_DIR, TABLE_DIR, MODEL_DIR, LOG_DIR)) {
  if (dir.exists(d)) unlink(d, recursive = TRUE)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

cat("Saving outputs to:\n")
cat("  Plots:  ", PLOT_DIR, "\n")
cat("  Tables: ", TABLE_DIR, "\n")
cat("  Models: ", MODEL_DIR, "\n")
cat("  Logs:   ", LOG_DIR, "\n")

# load data
TEST_PATH <- file.path(DATA_DIR, "ukb_test_drop_correlation_score.rds")
ukb_test_drop_high_correlation <- readRDS(TEST_PATH)
dat <- ukb_test_drop_high_correlation
rm(ukb_test_drop_high_correlation)

dat$cvd <- as.numeric(dat$cvd)

# dataset summary
dataset_summary <- data.frame(
  metric = c("n_rows", "n_columns"),
  value  = c(nrow(dat), ncol(dat))
)
write.csv(dataset_summary, file.path(TABLE_DIR, "q1_5_dataset_summary.csv"), row.names = FALSE)

variables <- setdiff(colnames(dat), "cvd")
write.csv(data.frame(variable = variables), file.path(TABLE_DIR, "q1_5_variables_tested.csv"), row.names = FALSE)

# CVD prevalence
cvd_complete <- dat %>% filter(!is.na(cvd))

cvd_prevalence_summary <- data.frame(
  metric = c("n_non_missing_cvd", "n_cvd_cases", "cvd_prevalence_percent"),
  value  = c(nrow(cvd_complete), sum(cvd_complete$cvd == 1), mean(cvd_complete$cvd == 1) * 100)
)
write.csv(cvd_prevalence_summary, file.path(TABLE_DIR, "q1_5_cvd_prevalence_summary.csv"), row.names = FALSE)

cvd_prevalence_table <- data.frame(
  outcome = c("No CVD", "CVD"),
  count   = c(sum(cvd_complete$cvd == 0), sum(cvd_complete$cvd == 1))
) %>% mutate(percent = round(100 * count / sum(count), 2))

write.csv(cvd_prevalence_table, file.path(TABLE_DIR, "q1_5_cvd_prevalence_table.csv"), row.names = FALSE)

cvd_prevalence_html <- kable(cvd_prevalence_table, caption = "Prevalence of CVD in the dataset") %>%
  kable_styling(full_width = FALSE, position = "left")
save_kable(cvd_prevalence_html, file.path(TABLE_DIR, "q1_5_cvd_prevalence_table.html"))

p_cvd_prev <- ggplot(cvd_prevalence_table, aes(x = outcome, y = percent)) +
  geom_col(fill = "steelblue") +
  labs(x = "CVD outcome", y = "Prevalence (%)", title = "Prevalence of CVD") +
  theme_minimal(base_size = 13)

saveRDS(p_cvd_prev, file.path(MODEL_DIR, "q1_5_cvd_prevalence_plot.rds"))
ggsave(file.path(PLOT_DIR, "q1_5_cvd_prevalence_bar_plot.png"), plot = p_cvd_prev, width = 8, height = 6, dpi = 300)
ggsave(file.path(PLOT_DIR, "q1_5_cvd_prevalence_bar_plot.pdf"), plot = p_cvd_prev, width = 8, height = 6)
cat("  [plot saved] q1_5_cvd_prevalence_bar_plot.png/.pdf\n")

# univariate logistic regression
run_uni_logit <- function(var, data) {
  temp <- data[, c("cvd", var), drop = FALSE]
  temp <- temp[complete.cases(temp), , drop = FALSE]
  if (nrow(temp) == 0 || length(unique(temp[[var]])) < 2) return(NULL)
  fit <- try(glm(as.formula(paste("cvd ~", var)), data = temp, family = binomial()), silent = TRUE)
  if (inherits(fit, "try-error")) return(NULL)
  sm <- summary(fit)$coefficients
  if (nrow(sm) < 2) return(NULL)
  beta <- sm[2, 1]; se <- sm[2, 2]; pval <- sm[2, 4]
  data.frame(
    variable   = var,
    odds_ratio = exp(beta),
    ci_low     = exp(beta - 1.96 * se),
    ci_high    = exp(beta + 1.96 * se),
    p_value    = pval
  )
}

n_cores      <- max(1, detectCores() - 1)
results_list <- mclapply(variables, run_uni_logit, data = dat, mc.cores = n_cores)
saveRDS(results_list, file.path(MODEL_DIR, "q1_5_univariate_logit_results_list.rds"))

results_df <- bind_rows(results_list) %>% arrange(p_value)
write.csv(results_df, file.path(TABLE_DIR, "q1_5_univariate_logistic_results_all.csv"), row.names = FALSE)
saveRDS(results_df,   file.path(MODEL_DIR, "q1_5_univariate_logistic_results_all.rds"))

# significant predictors table
sig_table <- results_df %>%
  filter(p_value < 0.05) %>%
  mutate(
    `Odds Ratio` = round(odds_ratio, 2),
    `95% CI`     = paste0("(", round(ci_low, 2), ", ", round(ci_high, 2), ")"),
    `P-value`    = signif(p_value, 3)
  ) %>%
  select(Predictor = variable, `Odds Ratio`, `95% CI`, `P-value`) %>%
  arrange(`P-value`)

write.csv(sig_table, file.path(TABLE_DIR, "q1_5_significant_predictors_table.csv"), row.names = FALSE)

sig_html <- kable(sig_table, caption = "Significant predictors of CVD (univariate logistic regression)") %>%
  kable_styling(full_width = FALSE, position = "left")
save_kable(sig_html, file.path(TABLE_DIR, "q1_5_significant_predictors_table.html"))

# forest plot - all significant
plot_df <- results_df %>%
  filter(p_value < 0.05) %>%
  arrange(odds_ratio) %>%
  mutate(variable = factor(variable, levels = variable))

write.csv(plot_df, file.path(TABLE_DIR, "q1_5_significant_predictors_plot_data.csv"), row.names = FALSE)

p_sig <- ggplot(plot_df, aes(x = odds_ratio, y = variable)) +
  geom_point(color = "darkgreen", size = 2.8) +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.2, orientation = "y", color = "darkgreen") +
  geom_vline(xintercept = 1, linetype = "dashed", color = "red") +
  labs(x = "Odds ratio (95% Wald CI)", y = "Predictor",
       title = "Univariate logistic regression: significant predictors") +
  theme_minimal(base_size = 13)

saveRDS(p_sig, file.path(MODEL_DIR, "q1_5_significant_predictors_plot.rds"))
ggsave(file.path(PLOT_DIR, "q1_5_significant_predictors_forest_plot.png"), plot = p_sig, width = 12, height = 10, dpi = 300)
ggsave(file.path(PLOT_DIR, "q1_5_significant_predictors_forest_plot.pdf"), plot = p_sig, width = 12, height = 10)
cat("  [plot saved] q1_5_significant_predictors_forest_plot.png/.pdf\n")

# forest plot - top 20
plot_df_top20 <- results_df %>%
  filter(p_value < 0.05) %>%
  slice_min(order_by = p_value, n = 20) %>%
  arrange(odds_ratio) %>%
  mutate(variable = factor(variable, levels = variable))

write.csv(plot_df_top20, file.path(TABLE_DIR, "q1_5_top20_significant_predictors_plot_data.csv"), row.names = FALSE)

p_top20 <- ggplot(plot_df_top20, aes(x = odds_ratio, y = variable)) +
  geom_point(color = "darkgreen", size = 2.8) +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.2, orientation = "y", color = "darkgreen") +
  geom_vline(xintercept = 1, linetype = "dashed", color = "red") +
  labs(x = "Odds ratio (95% Wald CI)", y = "Predictor", title = "Top 20 significant predictors") +
  theme_minimal(base_size = 13)

saveRDS(p_top20, file.path(MODEL_DIR, "q1_5_top20_significant_predictors_plot.rds"))
ggsave(file.path(PLOT_DIR, "q1_5_top20_significant_predictors_forest_plot.png"), plot = p_top20, width = 12, height = 8, dpi = 300)
ggsave(file.path(PLOT_DIR, "q1_5_top20_significant_predictors_forest_plot.pdf"), plot = p_top20, width = 12, height = 8)
cat("  [plot saved] q1_5_top20_significant_predictors_forest_plot.png/.pdf\n")

# manhattan plot
manhattan_df <- results_df %>%
  filter(!is.na(p_value)) %>%
  mutate(
    neg_log10_p = -log10(p_value),
    significant = p_value < 0.05,
    index       = row_number()
  )

bonferroni_threshold <- -log10(0.05 / nrow(manhattan_df))

# cap = just above the 4th highest value so top outliers are truncated
# but the rest of significant points are visible
sorted_vals <- sort(manhattan_df$neg_log10_p, decreasing = TRUE)
MAX_Y       <- ceiling(sorted_vals[min(4, length(sorted_vals))]) + 5
MAX_Y       <- max(MAX_Y, ceiling(bonferroni_threshold) + 2)
cat(sprintf("  Manhattan plot Y cap: %.0f\n", MAX_Y))

manhattan_df <- manhattan_df %>%
  mutate(
    neg_log10_p_plot = pmin(neg_log10_p, MAX_Y),
    truncated        = neg_log10_p > MAX_Y
  )

p_manhattan <- ggplot(manhattan_df, aes(x = index, y = neg_log10_p_plot, color = significant)) +
  geom_point(size = 1.8, alpha = 0.8) +
  # truncated points shown as triangles at the cap
  geom_point(
    data   = filter(manhattan_df, truncated),
    aes(x = index, y = MAX_Y),
    shape  = 24, size = 3.5, fill = "darkgreen", color = "black"
  ) +
  # labels for truncated points showing real value
  geom_text_repel(
    data        = filter(manhattan_df, truncated),
    aes(y       = MAX_Y,
        label   = paste0(variable, "\n(-log10p = ", round(neg_log10_p, 0), ")")),
    size        = 3, color = "black", nudge_y = 1.5, max.overlaps = 20
  ) +
  geom_hline(yintercept = -log10(0.05),        linetype = "dashed", color = "blue", linewidth = 0.8) +
  geom_hline(yintercept = bonferroni_threshold, linetype = "dashed", color = "red",  linewidth = 0.8) +
  scale_color_manual(
    values = c("FALSE" = "grey60", "TRUE" = "darkgreen"),
    labels = c("FALSE" = "p >= 0.05", "TRUE" = "p < 0.05")
  ) +
  scale_y_continuous(limits = c(0, MAX_Y + 3), breaks = seq(0, MAX_Y, by = 5)) +
  annotate("text", x = max(manhattan_df$index) * 0.98, y = -log10(0.05) + 0.3,
           label = "p = 0.05", color = "blue", size = 3.5, hjust = 1) +
  annotate("text", x = max(manhattan_df$index) * 0.98, y = bonferroni_threshold + 0.3,
           label = paste0("Bonferroni (p = ", signif(0.05 / nrow(manhattan_df), 2), ")"),
           color = "red", size = 3.5, hjust = 1) +
  # labels for top non-truncated significant points
  geom_text_repel(
    data        = manhattan_df %>% filter(!truncated, significant) %>%
      slice_min(order_by = p_value, n = 10),
    aes(label   = variable),
    size        = 3, color = "black", max.overlaps = 20
  ) +
  labs(
    x        = "Predictor index",
    y        = expression(-log[10](p)),
    title    = "Manhattan plot - univariate logistic regression",
    subtitle = paste0("^ = value exceeds y-axis cap (", MAX_Y, "); real -log10(p) shown in label"),
    color    = NULL
  ) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "top")

saveRDS(p_manhattan, file.path(MODEL_DIR, "q1_5_manhattan_plot.rds"))
ggsave(file.path(PLOT_DIR, "q1_5_manhattan_plot.png"), plot = p_manhattan, width = 14, height = 6, dpi = 300)
ggsave(file.path(PLOT_DIR, "q1_5_manhattan_plot.pdf"), plot = p_manhattan, width = 14, height = 6)
cat("  [plot saved] q1_5_manhattan_plot.png/.pdf\n")

write.csv(manhattan_df, file.path(TABLE_DIR, "q1_5_manhattan_plot_data.csv"), row.names = FALSE)

# random forest importance
rf_dat     <- dat[complete.cases(dat), , drop = FALSE]
rf_dat$cvd <- as.factor(rf_dat$cvd)
char_vars  <- names(rf_dat)[sapply(rf_dat, is.character)]
rf_dat[char_vars] <- lapply(rf_dat[char_vars], as.factor)

write.csv(data.frame(character_variable = char_vars),
          file.path(TABLE_DIR, "q1_5_rf_character_variables_converted_to_factor.csv"), row.names = FALSE)

set.seed(123)
rf_model <- ranger(cvd ~ ., data = rf_dat, num.trees = 500, importance = "permutation", probability = TRUE)
saveRDS(rf_model, file.path(MODEL_DIR, "q1_5_ranger_model.rds"))

imp_df <- data.frame(
  predictor  = names(rf_model$variable.importance),
  importance = as.numeric(rf_model$variable.importance)
)
write.csv(imp_df, file.path(TABLE_DIR, "q1_5_random_forest_variable_importance_all.csv"), row.names = FALSE)

plot_imp <- imp_df %>%
  arrange(desc(importance)) %>%
  slice_head(n = 20) %>%
  mutate(predictor = factor(predictor, levels = rev(predictor)))

write.csv(plot_imp, file.path(TABLE_DIR, "q1_5_random_forest_variable_importance_top20.csv"), row.names = FALSE)

p_rf_imp <- ggplot(plot_imp, aes(x = importance, y = predictor)) +
  geom_col(fill = "steelblue") +
  labs(x = "Permutation importance", y = "Predictor",
       title = "Top 20 predictors from ranger random forest") +
  theme_minimal(base_size = 13)

saveRDS(p_rf_imp, file.path(MODEL_DIR, "q1_5_random_forest_importance_plot.rds"))
ggsave(file.path(PLOT_DIR, "q1_5_random_forest_importance_top20.png"), plot = p_rf_imp, width = 12, height = 8, dpi = 300)
ggsave(file.path(PLOT_DIR, "q1_5_random_forest_importance_top20.pdf"), plot = p_rf_imp, width = 12, height = 8)
cat("  [plot saved] q1_5_random_forest_importance_top20.png/.pdf\n")

# random forest AUC
rf_dat     <- dat[complete.cases(dat), , drop = FALSE]
rf_dat$cvd <- as.factor(rf_dat$cvd)

set.seed(123)
train_idx    <- sample(seq_len(nrow(rf_dat)), size = 0.7 * nrow(rf_dat))
train        <- rf_dat[train_idx, ]
test         <- rf_dat[-train_idx, ]

rf_model_auc <- ranger(cvd ~ ., data = train, num.trees = 500, probability = TRUE, importance = "permutation")
saveRDS(rf_model_auc, file.path(MODEL_DIR, "q1_5_ranger_auc_model.rds"))

pred <- predict(rf_model_auc, data = test)$predictions[, "1"]
write.csv(data.frame(observed = test$cvd, predicted_probability = pred),
          file.path(TABLE_DIR, "q1_5_random_forest_auc_predictions.csv"), row.names = FALSE)

roc_obj <- roc(test$cvd, pred, quiet = TRUE)
auc_val <- auc(roc_obj)
print(auc_val)

write.csv(data.frame(model = "Random Forest", auc = as.numeric(auc_val),
                     n_train = nrow(train), n_test = nrow(test)),
          file.path(TABLE_DIR, "q1_5_random_forest_auc_results.csv"), row.names = FALSE)
saveRDS(roc_obj, file.path(MODEL_DIR, "q1_5_random_forest_roc_object.rds"))

for (ext in c("png", "pdf")) {
  if (ext == "png") {
    png(file.path(PLOT_DIR, "q1_5_random_forest_auc_roc_curve.png"), width = 1800, height = 1600, res = 220)
  } else {
    pdf(file.path(PLOT_DIR, "q1_5_random_forest_auc_roc_curve.pdf"), width = 1800/220, height = 1600/220)
  }
  plot(roc_obj, main = paste("Random Forest AUC =", round(auc_val, 3)))
  dev.off()
}
cat("  [plot saved] q1_5_random_forest_auc_roc_curve.png/.pdf\n")

# save workspace
save(dat, results_list, results_df, sig_table, plot_df, plot_df_top20,
     manhattan_df, rf_dat, rf_model, imp_df, plot_imp, rf_model_auc,
     pred, roc_obj, auc_val,
     file = file.path(MODEL_DIR, "q1_5_workspace_objects.RData"))

save.image(file = file.path(MODEL_DIR, "q1_5_full_workspace.RData"))

sink(file.path(LOG_DIR, "q1_5_session_info.txt"))
sessionInfo()
sink()

all_saved_files <- c(
  list.files(PLOT_DIR,  recursive = TRUE, full.names = TRUE),
  list.files(TABLE_DIR, recursive = TRUE, full.names = TRUE),
  list.files(MODEL_DIR, recursive = TRUE, full.names = TRUE),
  list.files(LOG_DIR,   recursive = TRUE, full.names = TRUE)
)
writeLines(all_saved_files, file.path(LOG_DIR, "q1_5_saved_files_manifest.txt"))

cat("\nAll outputs saved successfully.\n")
print(all_saved_files)