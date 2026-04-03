# UKB - Missingness & Prefer Not To Answer filtering pipeline
rm(list = ls())

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
  library(gridExtra)
})

# Load data
df <- readRDS("../outputs/ukb_processed.rds")
df <- as.data.frame(df)

cat("Starting dimensions:", nrow(df), "x", ncol(df), "\n")

# Add eid
if ("eid" %in% names(df)) {
  df$eid <- as.character(df$eid)
} else if (!is.null(rownames(df)) && all(rownames(df) != "")) {
  df$eid <- rownames(df)
  df$eid <- as.character(df$eid)
} else {
  stop("No 'eid' column found and rownames are not usable.")
}

df <- df %>% dplyr::select(eid, dplyr::everything())

if (anyDuplicated(df$eid) > 0) stop("Duplicate eid values found.")

# Elbow detection
find_elbow <- function(values) {
  sorted_vals <- sort(values, decreasing = TRUE)
  n <- length(sorted_vals)
  x <- (seq_len(n) - 1) / (n - 1)
  y <- (sorted_vals - min(sorted_vals)) / (max(sorted_vals) - min(sorted_vals) + 1e-10)
  line_vec  <- c(x[n] - x[1], y[n] - y[1])
  line_unit <- line_vec / sqrt(sum(line_vec^2))
  perp_dist <- sapply(seq_len(n), function(i) {
    pt_vec <- c(x[i] - x[1], y[i] - y[1])
    abs(line_unit[1] * pt_vec[2] - line_unit[2] * pt_vec[1])
  })
  sorted_vals[which.max(perp_dist)]
}

# Elbow plot
make_elbow_plot <- function(values, x_label, y_label, title, color,
                            unit_label = "items", elbow_val = NULL) {
  if (is.null(elbow_val)) elbow_val <- find_elbow(values)
  n_excluded   <- sum(values > elbow_val, na.rm = TRUE)
  pct_excluded <- n_excluded / length(values) * 100
  plot_df <- data.frame(value = as.numeric(values)) %>%
    arrange(desc(value)) %>%
    mutate(rank = row_number())
  elbow_rank <- which.min(abs(plot_df$value - elbow_val))
  annot_text <- sprintf("Elbow: %.1f%%\nExcludes: %d %s (%.1f%%)",
                        elbow_val, n_excluded, unit_label, pct_excluded)
  ggplot(plot_df, aes(x = rank, y = value)) +
    geom_line(color = color, linewidth = 0.8) +
    geom_point(size = 0.4, color = color, alpha = 0.6) +
    geom_vline(xintercept = elbow_rank, linetype = "dashed", color = "black", linewidth = 0.7) +
    geom_hline(yintercept = elbow_val,  linetype = "dashed", color = "black", linewidth = 0.7) +
    annotate("point", x = elbow_rank, y = elbow_val, size = 4, color = "black") +
    annotate("text",
             x     = elbow_rank + max(plot_df$rank) * 0.03,
             y     = elbow_val  + max(plot_df$value, na.rm = TRUE) * 0.05,
             label = annot_text, size = 3, hjust = 0, color = "black") +
    labs(title = title, x = x_label, y = y_label) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold", size = 10),
          panel.grid.minor = element_blank())
}

# Step 1: drop variables with too many PNTA (-1)
cat("STEP 1: Drop variables with excess PNTA (-1)\n")

screen_vars_step1 <- setdiff(names(df), "eid")
pct_neg1_var      <- sapply(df[, screen_vars_step1, drop = FALSE], function(x) {
  sum(x == -1, na.rm = TRUE) / nrow(df) * 100
})
elbow_neg1_var    <- find_elbow(pct_neg1_var)

cat(sprintf("Optimal PNTA threshold (variables): %.1f%%\n", elbow_neg1_var))

vars_remove_pnta <- names(pct_neg1_var[pct_neg1_var > elbow_neg1_var])
cat(sprintf("Variables dropped: %d\n", length(vars_remove_pnta)))
print(vars_remove_pnta)

p1 <- make_elbow_plot(pct_neg1_var, "Variables (ranked)", "% PNTA (-1)",
                      "Step 1: PNTA by variable", "#F39C12", "variables", elbow_neg1_var)

df1 <- df %>% dplyr::select(-dplyr::any_of(vars_remove_pnta))
cat(sprintf("Dimensions after Step 1: %d x %d\n", nrow(df1), ncol(df1)))

# Step 2: drop individuals with any remaining -1
cat("STEP 2: Drop individuals with any remaining PNTA (-1)\n")

screen_vars_step2 <- setdiff(names(df1), "eid")
has_neg1_row      <- apply(df1[, screen_vars_step2, drop = FALSE], 1, function(x) any(x == -1, na.rm = TRUE))
n_removed_step2   <- sum(has_neg1_row)

cat(sprintf("Individuals dropped: %d (%.1f%%)\n", n_removed_step2, n_removed_step2 / nrow(df1) * 100))

df2 <- df1[!has_neg1_row, , drop = FALSE]
cat(sprintf("Dimensions after Step 2: %d x %d\n", nrow(df2), ncol(df2)))

# Step 3: drop variables with too much missingness
cat("STEP 3: Drop variables with excess missingness\n")

screen_vars_step3 <- setdiff(names(df2), "eid")
pct_miss_var      <- sapply(df2[, screen_vars_step3, drop = FALSE], function(x) {
  sum(is.na(x)) / nrow(df2) * 100
})
elbow_miss_var    <- find_elbow(pct_miss_var)

cat(sprintf("Optimal missingness threshold (variables): %.1f%%\n", elbow_miss_var))

vars_remove_miss <- names(pct_miss_var[pct_miss_var > elbow_miss_var])
cat(sprintf("Variables dropped: %d\n", length(vars_remove_miss)))
print(vars_remove_miss)

p2 <- make_elbow_plot(pct_miss_var, "Variables (ranked)", "% Missing",
                      "Step 3: Missingness by variable", "#E74C3C", "variables", elbow_miss_var)

df3 <- df2 %>% dplyr::select(-dplyr::any_of(vars_remove_miss))
cat(sprintf("Dimensions after Step 3: %d x %d\n", nrow(df3), ncol(df3)))

# Step 4: drop individuals with too much missingness
cat("STEP 4: Drop individuals with excess missingness\n")

screen_vars_step4 <- setdiff(names(df3), "eid")
pct_miss_row      <- apply(df3[, screen_vars_step4, drop = FALSE], 1, function(x) {
  sum(is.na(x)) / length(x) * 100
})
elbow_miss_row    <- find_elbow(pct_miss_row)

cat(sprintf("Optimal missingness threshold (individuals): %.1f%%\n", elbow_miss_row))

rows_remove_miss <- pct_miss_row > elbow_miss_row
cat(sprintf("Individuals dropped: %d (%.1f%%)\n",
            sum(rows_remove_miss), sum(rows_remove_miss) / nrow(df3) * 100))

p3 <- make_elbow_plot(pct_miss_row, "Participants (ranked)", "% Missing",
                      "Step 4: Missingness by participant", "#2980B9", "participants", elbow_miss_row)

df4 <- df3[!rows_remove_miss, , drop = FALSE]
cat(sprintf("Dimensions after Step 4: %d x %d\n", nrow(df4), ncol(df4)))

# Step 5: bring back selected columns from original df
cat("STEP 5: Add back selected BHI / CVHI / smoking / alcohol / MET columns\n")

bhi_vars <- c("biochem_hba1c","biochem_hdl","biochem_ldl_direct","biochem_triglycerides",
              "systolic_bp","diastolic_bp","cardiac_pulse_rate","biochem_crp","igf1",
              "alanine_aminotransferase","aspartate_aminotransferase","gamma_glutamyltransferase",
              "creatinine","DASH_score","HSI")

cvhi_vars <- c("bmi","biochem_cholesterol","biochem_hdl","biochem_glucose","biochem_hba1c",
               "systolic_bp","diastolic_bp","med_cholesterol_bp_diabetes_hormones","sleep_duration")

lifestyle_vars <- c("pack_year_index","alcohol_freq_6plus_units","total_unit_alcohol_per_week",
                    "MET_total","HSI")

transfer_vars <- unique(c(bhi_vars, cvhi_vars, lifestyle_vars))
transfer_vars <- intersect(transfer_vars, names(df))

cat("Requested columns from original df:\n")
print(transfer_vars)

if (length(transfer_vars) == 0) stop("None of the requested transfer variables are present in df.")

df_transfer <- df %>% dplyr::select(eid, dplyr::all_of(transfer_vars))
df_transfer <- df4 %>% dplyr::select(eid) %>% dplyr::left_join(df_transfer, by = "eid")

if (nrow(df_transfer) != nrow(df4)) stop("Join by eid failed: row count mismatch.")

has_neg1_selected <- apply(df_transfer[, setdiff(names(df_transfer), "eid"), drop = FALSE], 1,
                           function(x) any(x == -1, na.rm = TRUE))

cat(sprintf("Participants to drop due to -1 in selected columns: %d (%.1f%%)\n",
            sum(has_neg1_selected), 100 * sum(has_neg1_selected) / nrow(df_transfer)))

df4_keep         <- df4[!has_neg1_selected, , drop = FALSE]
df_transfer_keep <- df_transfer[!has_neg1_selected, , drop = FALSE]

new_cols <- setdiff(names(df_transfer_keep), c(names(df4_keep), "eid"))

cat("Columns newly added to df4:\n")
print(new_cols)

df5 <- df4_keep %>%
  dplyr::left_join(df_transfer_keep %>% dplyr::select(eid, dplyr::all_of(new_cols)), by = "eid")

cat(sprintf("Dimensions after Step 5: %d x %d\n", nrow(df5), ncol(df5)))

# Quick checks
cat("QUICK CHECKS\n")

cat("Any duplicated eid in final df5? ", anyDuplicated(df5$eid) > 0, "\n")

check_cols           <- intersect(transfer_vars, names(df5))
remaining_neg1_rows  <- apply(df5[, check_cols, drop = FALSE], 1, function(x) any(x == -1, na.rm = TRUE))

cat("Remaining participants with -1 in selected columns: ", sum(remaining_neg1_rows), "\n")
cat("NA counts in selected columns:\n")
print(sort(colSums(is.na(df5[, check_cols, drop = FALSE])), decreasing = TRUE))

# Save plots as PNG and PDF
panel <- gridExtra::arrangeGrob(p1, p2, p3, ncol = 3)

ggsave("../outputs/ukb_filtering_plots.png", panel, width = 21, height = 10, dpi = 300)
ggsave("../outputs/ukb_filtering_plots.pdf", panel, width = 21, height = 10)

# Summary

cat(sprintf("Original df:                           %d x %d\n", nrow(df),  ncol(df)))
cat(sprintf("After Step 1 (vars PNTA):              %d x %d\n", nrow(df1), ncol(df1)))
cat(sprintf("After Step 2 (indiv PNTA):             %d x %d\n", nrow(df2), ncol(df2)))
cat(sprintf("After Step 3 (vars missingness):       %d x %d\n", nrow(df3), ncol(df3)))
cat(sprintf("After Step 4 (indiv missingness):      %d x %d\n", nrow(df4), ncol(df4)))
cat(sprintf("After Step 5 (add back selected vars): %d x %d\n", nrow(df5), ncol(df5)))

cat("\nSelected groups:\n")
cat(sprintf("BHI vars requested:        %d\n", length(bhi_vars)))
cat(sprintf("CVHI vars requested:       %d\n", length(cvhi_vars)))
cat(sprintf("Lifestyle vars requested:  %d\n", length(lifestyle_vars)))
cat(sprintf("Total existing requested:  %d\n", length(transfer_vars)))
cat(sprintf("New columns actually added:%d\n", length(new_cols)))

# Save output
saveRDS(df5, "../outputs/ukb_filtered_NA.rds")

print("NA finished")