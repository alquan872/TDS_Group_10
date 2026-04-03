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

ukb <- readRDS("../../2_Imputation/outputs/ukb_imputed_all.rds")
output_dir <- file.path("..", "outputs")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(corrplot)
})

ukb <- as.data.frame(ukb)

# -------------------------------
# 1. Protected outcomes
# -------------------------------
protected_vars <- intersect(c(
  "cvd"
), names(ukb))

# -------------------------------
# 2. classify variable classes from original data types
# -------------------------------

candidate_vars <- setdiff(names(ukb), protected_vars)

numeric_vars <- candidate_vars[sapply(ukb[candidate_vars], is.numeric)]

categorical_vars <- candidate_vars[
  sapply(ukb[candidate_vars], function(x) is.factor(x) || is.character(x))
]

index_vars <- character(0)

classification_check <- data.frame(
  variable = names(ukb),
  original_class = sapply(ukb, function(x) paste(class(x), collapse = ",")),
  assigned_type = ifelse(
    names(ukb) %in% protected_vars, "protected",
    ifelse(
      names(ukb) %in% numeric_vars, "numeric",
      ifelse(
        names(ukb) %in% categorical_vars, "categorical",
        ifelse(names(ukb) %in% index_vars, "index", "unclassified")
      )
    )
  ),
  stringsAsFactors = FALSE
)

print(classification_check)
# -------------------------------
# 3. Select analysis data
# -------------------------------
analysis_vars <- unique(c(numeric_vars, categorical_vars, index_vars))

df_cor <- ukb %>%
  dplyr::select(dplyr::any_of(analysis_vars))

cat("Number of selected variables:", ncol(df_cor), "\n")

# -------------------------------
# 4. Type conversion
# -------------------------------
for (v in intersect(numeric_vars, names(df_cor))) {
  df_cor[[v]] <- suppressWarnings(as.numeric(df_cor[[v]]))
}

for (v in intersect(index_vars, names(df_cor))) {
  df_cor[[v]] <- suppressWarnings(as.numeric(df_cor[[v]]))
}

for (v in intersect(categorical_vars, names(df_cor))) {
  df_cor[[v]] <- as.factor(df_cor[[v]])
}

cat("\nVariable classes summary:\n")
print(table(sapply(df_cor, class)))

# -------------------------------
# 5. Skip missingness check
# Because this is imputed data
# -------------------------------
cat("\nImputed dataset detected: skip complete-case filtering.\n")
cat("Dimensions used for correlation analysis:",
    nrow(df_cor), "x", ncol(df_cor), "\n")

# -------------------------------
# 6. Split numeric/index and categorical
# -------------------------------
num_idx_vars <- intersect(c(numeric_vars, index_vars), names(df_cor))
cat_vars     <- intersect(categorical_vars, names(df_cor))

df_num <- df_cor[, num_idx_vars, drop = FALSE]
df_cat <- df_cor[, cat_vars, drop = FALSE]

# -------------------------------
# 7. Remove zero-variance numeric/index variables
# -------------------------------
zero_var_num <- names(df_num)[sapply(df_num, function(x) {
  is.numeric(x) && sd(x, na.rm = TRUE) == 0
})]

if (length(zero_var_num) > 0) {
  cat("\nRemoving zero-variance numeric/index variables:\n")
  print(zero_var_num)
  df_num <- df_num[, !names(df_num) %in% zero_var_num, drop = FALSE]
  num_idx_vars <- names(df_num)
}

# -------------------------------
# 8. Remove single-level categorical variables
# -------------------------------
single_level_cat <- names(df_cat)[sapply(df_cat, function(x) {
  length(unique(x[!is.na(x)])) <= 1
})]

if (length(single_level_cat) > 0) {
  cat("\nRemoving single-level categorical variables:\n")
  print(single_level_cat)
  df_cat <- df_cat[, !names(df_cat) %in% single_level_cat, drop = FALSE]
  cat_vars <- names(df_cat)
}

cat("\nFinal numeric/index variable count:", length(num_idx_vars), "\n")
cat("Final categorical variable count:", length(cat_vars), "\n")

# -------------------------------
# 9. Pearson for numeric/index
# -------------------------------
if (length(num_idx_vars) > 0) {
  cor_num <- cor(df_num, method = "pearson", use = "pairwise.complete.obs")
} else {
  cor_num <- NULL
}

# -------------------------------
# 10. Cramer's V for categorical
# -------------------------------
cramers_v <- function(x, y) {
  tab <- table(x, y)
  
  if (nrow(tab) < 2 || ncol(tab) < 2) return(NA_real_)
  
  chi <- suppressWarnings(chisq.test(tab, correct = FALSE))
  
  n <- sum(tab)
  k <- min(nrow(tab), ncol(tab))
  
  if (n == 0 || k <= 1) return(NA_real_)
  
  sqrt(as.numeric(chi$statistic) / (n * (k - 1)))
}

if (length(cat_vars) > 0) {
  cramer_matrix <- matrix(
    NA_real_,
    nrow = length(cat_vars),
    ncol = length(cat_vars),
    dimnames = list(cat_vars, cat_vars)
  )
  
  for (i in seq_along(cat_vars)) {
    for (j in i:length(cat_vars)) {
      v1 <- cat_vars[i]
      v2 <- cat_vars[j]
      
      if (i == j) {
        cramer_matrix[i, j] <- 1
      } else {
        val <- cramers_v(df_cat[[v1]], df_cat[[v2]])
        cramer_matrix[i, j] <- val
        cramer_matrix[j, i] <- val
      }
    }
  }
} else {
  cramer_matrix <- NULL
}

# -------------------------------
# 11. Eta for numeric/index vs categorical
# -------------------------------
eta_correlation <- function(y, x) {
  x <- as.factor(x)
  
  if (!is.numeric(y)) return(NA_real_)
  if (sd(y, na.rm = TRUE) == 0) return(NA_real_)
  if (length(unique(x[!is.na(x)])) <= 1) return(NA_real_)
  
  grand_mean <- mean(y, na.rm = TRUE)
  
  group_stats <- split(y, x)
  group_stats <- group_stats[lengths(group_stats) > 0]
  
  ss_between <- sum(sapply(group_stats, function(g) {
    length(g) * (mean(g, na.rm = TRUE) - grand_mean)^2
  }))
  
  ss_total <- sum((y - grand_mean)^2, na.rm = TRUE)
  
  if (ss_total == 0) return(NA_real_)
  
  sqrt(ss_between / ss_total)
}

if (length(num_idx_vars) > 0 && length(cat_vars) > 0) {
  num_cat_matrix <- matrix(
    NA_real_,
    nrow = length(num_idx_vars),
    ncol = length(cat_vars),
    dimnames = list(num_idx_vars, cat_vars)
  )
  
  for (i in seq_along(num_idx_vars)) {
    for (j in seq_along(cat_vars)) {
      num_cat_matrix[i, j] <- eta_correlation(
        df_cor[[num_idx_vars[i]]],
        df_cor[[cat_vars[j]]]
      )
    }
  }
} else {
  num_cat_matrix <- NULL
}

# -------------------------------
# 12. Combine full association matrix
# -------------------------------
if (!is.null(cor_num) && !is.null(cramer_matrix) && !is.null(num_cat_matrix)) {
  top <- cbind(cor_num, num_cat_matrix)
  bottom <- cbind(t(num_cat_matrix), cramer_matrix)
  assoc_mat <- rbind(top, bottom)
} else if (!is.null(cor_num) && is.null(cramer_matrix)) {
  assoc_mat <- cor_num
} else if (is.null(cor_num) && !is.null(cramer_matrix)) {
  assoc_mat <- cramer_matrix
} else {
  stop("No valid variables available to build the association matrix.")
}

diag(assoc_mat) <- 1

# -------------------------------
# 13. Remove variables with NA/NaN/Inf in final matrix
# -------------------------------
bad_vars <- rownames(assoc_mat)[apply(assoc_mat, 1, function(x) {
  any(is.na(x) | is.nan(x) | is.infinite(x))
})]

if (length(bad_vars) > 0) {
  cat("\nRemoving variables with invalid values in final matrix:\n")
  print(bad_vars)
  
  assoc_mat <- assoc_mat[
    !rownames(assoc_mat) %in% bad_vars,
    !colnames(assoc_mat) %in% bad_vars,
    drop = FALSE
  ]
}

diag(assoc_mat) <- 1

cat("\nFinal matrix dimension:", dim(assoc_mat)[1], "x", dim(assoc_mat)[2], "\n")
cat("Remaining NA:", sum(is.na(assoc_mat)), "\n")
cat("Remaining NaN:", sum(is.nan(assoc_mat)), "\n")
cat("Remaining Inf:", sum(is.infinite(assoc_mat)), "\n")


# Save PNG
png(
  filename = file.path(output_dir, "mixed_association_heatmap.png"),
  width = 4000,
  height = 4000,
  res = 300
)

corrplot(
  assoc_mat,
  method = "color",
  type = "upper",
  order = "hclust",
  col = colorRampPalette(c("#3B4CC0", "white", "#B40426"))(200),
  tl.cex = 0.55,
  tl.col = "black",
  cl.cex = 0.7,
  diag = FALSE
)

title(
  main = "Mixed-Type Association Heatmap",
  sub = "Pearson for numeric/index, Cramer's V for categorical, Eta for numeric-categorical"
)

dev.off()


# Save PDF
pdf(
  file = file.path(output_dir, "mixed_association_heatmap.pdf"),
  width = 14,
  height = 14
)

corrplot(
  assoc_mat,
  method = "color",
  type = "upper",
  order = "hclust",
  col = colorRampPalette(c("#3B4CC0", "white", "#B40426"))(200),
  tl.cex = 0.55,
  tl.col = "black",
  cl.cex = 0.7,
  diag = FALSE
)

title(
  main = "Mixed-Type Association Heatmap",
  sub = "Pearson for numeric/index, Cramer's V for categorical, Eta for numeric-categorical"
)

dev.off()

assoc_long <- as.data.frame(as.table(assoc_mat))
names(assoc_long) <- c("Variable1", "Variable2", "Association")

# remove self pairs
assoc_long <- assoc_long %>%
  filter(Variable1 != Variable2)

# remove duplicated pairs (keep upper triangle)
assoc_long <- assoc_long %>%
  filter(as.character(Variable1) < as.character(Variable2))

strong_05 <- assoc_long %>%
  filter(abs(Association) >= 0.5) %>%
  arrange(desc(abs(Association)))

strong_07 <- assoc_long %>%
  filter(abs(Association) >= 0.7) %>%
  arrange(desc(abs(Association)))

strong_09 <- assoc_long %>%
  filter(abs(Association) >= 0.9) %>%
  arrange(desc(abs(Association)))

cat("\nAssociations ≥ 0.5:\n")
print(head(strong_05, 30))

cat("\nAssociations ≥ 0.7:\n")
print(head(strong_07, 30))

cat("\nAssociations ≥ 0.9:\n")
print(head(strong_09, 30))

# -------------------------------
# 15. Drop highly correlated columns from imputed train/val/test
# -------------------------------

# read from dataset subdirectory
ukb_all_imputed   <- readRDS("../../2_Imputation/outputs/ukb_imputed_all.rds")
ukb_train_imputed <- readRDS("../../2_Imputation/outputs/ukb_train_imputed.rds")
ukb_val_imputed   <- readRDS("../../2_Imputation/outputs/ukb_val_imputed.rds")
ukb_test_imputed  <- readRDS("../../2_Imputation/outputs/ukb_test_imputed.rds")

cols_to_drop <- c(
  "bmr",
  "biochem_cholesterol",
  "biochem_ldl_direct",
  "resp_fvc_best",
  "blood_hemoglobin_conc",
  "blood_reticulocyte_pct"
)

# -------------------------------
# 16. Further drop CVH / BHS score variables
# -------------------------------
score_vars_to_drop <- c(
  "CVH_nicotine_score",
  "CVH_bmi_score",
  "CVH_lipid_score",
  "CVH_glucose_score",
  "CVH_bp_score",
  "CVH_sleep_score",
  "CVH_score",
  "CVH_pa_score",
  "CVH_diet_score", 
  "BHS_metabolic",
  "BHS_cardiovascular",
  "BHS_immune",
  "BHS_liver",
  "BHS_kidney",
  "BHS"
)
# combine with previous dropped columns 
all_drop_vars <- unique(c(cols_to_drop, score_vars_to_drop))

cat("\nVariables to drop:\n")
print(all_drop_vars)

# apply dropping
ukb_all_dropped   <- ukb_all_imputed[,   !(names(ukb_all_imputed) %in% all_drop_vars), drop = FALSE]
ukb_train_dropped <- ukb_train_imputed[, !(names(ukb_train_imputed) %in% all_drop_vars), drop = FALSE]
ukb_val_dropped   <- ukb_val_imputed[,   !(names(ukb_val_imputed) %in% all_drop_vars), drop = FALSE]
ukb_test_dropped  <- ukb_test_imputed[,  !(names(ukb_test_imputed) %in% all_drop_vars), drop = FALSE]

# -------------------------------
# save dataframe
# -------------------------------
output_dir <- file.path("..", "outputs")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# -------------------------------
# save dataframe
# -------------------------------

write.csv(
  ukb_all_dropped,
  file.path(output_dir, "ukb_all_drop_correlation_score.csv"),
  row.names = FALSE
)

write.csv(
  ukb_train_dropped,
  file.path(output_dir, "ukb_train_drop_correlation_score.csv"),
  row.names = FALSE
)

write.csv(
  ukb_val_dropped,
  file.path(output_dir, "ukb_val_drop_correlation_score.csv"),
  row.names = FALSE
)

write.csv(
  ukb_test_dropped,
  file.path(output_dir, "ukb_test_drop_correlation_score.csv"),
  row.names = FALSE
)

saveRDS(
  ukb_all_dropped,
  file.path(output_dir, "ukb_all_drop_correlation_score.rds")
)

saveRDS(
  ukb_train_dropped,
  file.path(output_dir, "ukb_train_drop_correlation_score.rds")
)

saveRDS(
  ukb_val_dropped,
  file.path(output_dir, "ukb_val_drop_correlation_score.rds")
)

saveRDS(
  ukb_test_dropped,
  file.path(output_dir, "ukb_test_drop_correlation_score.rds")
)

cat("\nFiles saved successfully in ../outputs/ \n")