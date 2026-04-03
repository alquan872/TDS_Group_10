if (!interactive()) {
  setwd(dirname(normalizePath(commandArgs(trailingOnly=FALSE)[grep("--file=",commandArgs(trailingOnly=FALSE))][1] |> sub("--file=","",x=_))))
}
if (interactive()) {
  setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
}

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(dagitty)
  library(ggdag)
})

# directories
PLOT_DIR  <- "../outputs/plots"
TABLE_DIR <- "../outputs/tables"
MODEL_DIR <- "../outputs/models"
LOG_DIR   <- "../outputs/logs"

for (d in c(PLOT_DIR, TABLE_DIR, MODEL_DIR, LOG_DIR)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# load main dataset
ukb <- readRDS("../../3_Correlation/outputs/ukb_all_drop_correlation_score.rds")
cat("ukb loaded:", nrow(ukb), "rows,", ncol(ukb), "cols\n")

# FUNCTIONS

build_edges <- function(conf, vars, outcome) {
  dplyr::bind_rows(
    if (length(conf) > 0 && length(vars) > 0) expand.grid(from = conf, to = vars, stringsAsFactors = FALSE),
    if (length(conf) > 0) expand.grid(from = conf, to = outcome, stringsAsFactors = FALSE),
    if (length(vars) > 0) expand.grid(from = vars, to = outcome, stringsAsFactors = FALSE)
  ) %>%
    dplyr::filter(!is.na(from), !is.na(to), from != "", to != "") %>%
    dplyr::distinct()
}

build_dag <- function(edges, nodes) {
  edge_lines <- if (nrow(edges) > 0) paste(edges$from, "->", edges$to) else character(0)
  node_lines <- setdiff(nodes, unique(c(edges$from, edges$to)))
  dagitty::dagitty(paste0("dag {\n", paste(c(edge_lines, node_lines), collapse = "\n"), "\n}"))
}

set_coords <- function(dag, conf, vars, outcome) {
  x_conf <- if (length(conf) > 0) seq_along(conf) * 3 else numeric(0)
  x_vars <- if (length(vars) > 0) seq_along(vars) * 1.4 else numeric(0)
  x_out  <- if (length(x_vars) > 0) mean(x_vars) else if (length(x_conf) > 0) mean(x_conf) else 2
  dagitty::coordinates(dag) <- list(
    x = stats::setNames(c(x_conf, x_vars, x_out), c(conf, vars, outcome)),
    y = stats::setNames(c(rep(3, length(conf)), rep(2, length(vars)), 1), c(conf, vars, outcome))
  )
  dag
}

plot_dag <- function(dag, conf, vars, outcome, title) {
  ggdag::tidy_dagitty(dag) %>%
    dplyr::mutate(
      type = dplyr::case_when(
        name %in% conf    ~ "Confounder",
        name %in% vars    ~ "Variable",
        TRUE              ~ "Outcome"
      )
    ) %>%
    ggplot2::ggplot(ggplot2::aes(x, y, xend = xend, yend = yend)) +
    ggdag::geom_dag_edges() +
    ggdag::geom_dag_point(ggplot2::aes(fill = type), shape = 21, size = 10) +
    ggdag::geom_dag_text(ggplot2::aes(label = name)) +
    ggdag::theme_dag() +
    ggplot2::labs(title = title)
}

save_dag_plots <- function(p1, p2, prefix) {
  for (ext in c("png", "pdf")) {
    ggplot2::ggsave(file.path(PLOT_DIR, paste0(prefix, "_with_age_sex.", ext)),
                    plot = p1, width = 12, height = 7, dpi = 300)
    ggplot2::ggsave(file.path(PLOT_DIR, paste0(prefix, "_without_age_sex.", ext)),
                    plot = p2, width = 12, height = 7, dpi = 300)
  }
  cat("  [plots saved]", prefix, "\n")
}

run_dag <- function(selected_vars_raw, ukb, confounders, outcome, prefix, label) {
  
  cat("\n--", label, "--\n")
  
  selected_vars <- setdiff(selected_vars_raw, confounders)
  
  vars_present <- intersect(c(confounders, selected_vars, outcome), names(ukb))
  dat          <- ukb %>% dplyr::select(dplyr::all_of(vars_present))
  
  if ("sex" %in% names(dat))
    dat$sex <- ifelse(as.character(dat$sex) %in% c("Male", "male", "1"), 1, 0)
  if ("cvd" %in% names(dat))
    dat$cvd <- as.numeric(as.character(dat$cvd))
  
  confounders   <- intersect(confounders,   names(dat))
  selected_vars <- intersect(selected_vars, names(dat))
  
  dat_model <- dat %>%
    dplyr::select(dplyr::all_of(c(confounders, selected_vars, outcome))) %>%
    na.omit()
  
  if (nrow(dat_model) == 0)    stop(paste("No complete cases for", label))
  if (length(selected_vars) == 0) stop(paste("No variables found in data for", label))
  
  formula <- as.formula(paste(outcome, "~", paste(c(confounders, selected_vars), collapse = " + ")))
  fit     <- glm(formula, data = dat_model, family = binomial())
  
  coef_t  <- summary(fit)$coefficients
  coef_t  <- coef_t[rownames(coef_t) != "(Intercept)", , drop = FALSE]
  pvals   <- coef_t[, "Pr(>|z|)"]
  p_adj   <- p.adjust(pvals, method = "BH")
  
  sig_vars <- setdiff(names(p_adj)[p_adj < 0.05], confounders)
  if (length(sig_vars) == 0)
    sig_vars <- intersect(names(sort(p_adj))[1:5], selected_vars)
  
  cat("  Significant vars:", length(sig_vars), "\n")
  
  # DAG with confounders
  e1   <- build_edges(confounders, sig_vars, outcome)
  dag1 <- set_coords(build_dag(e1, c(confounders, sig_vars, outcome)),
                     confounders, sig_vars, outcome)
  p1   <- plot_dag(dag1, confounders, sig_vars, outcome, paste("DAG with age & sex -", label))
  
  # DAG without confounders
  e2   <- build_edges(character(0), sig_vars, outcome)
  dag2 <- set_coords(build_dag(e2, c(sig_vars, outcome)),
                     character(0), sig_vars, outcome)
  p2   <- plot_dag(dag2, character(0), sig_vars, outcome, paste("DAG without age & sex -", label))
  
  save_dag_plots(p1, p2, prefix)
  
  # save models and tables
  saveRDS(p1,  file.path(MODEL_DIR, paste0(prefix, "_dag_with_age_sex.rds")))
  saveRDS(p2,  file.path(MODEL_DIR, paste0(prefix, "_dag_without_age_sex.rds")))
  saveRDS(fit, file.path(MODEL_DIR, paste0(prefix, "_logistic_model.rds")))
  
  reg_summary <- data.frame(
    variable         = names(p_adj),
    p_value          = unname(pvals[names(p_adj)]),
    p_adj_bh         = unname(p_adj),
    retained_for_dag = names(p_adj) %in% sig_vars,
    stringsAsFactors = FALSE
  ) %>% dplyr::arrange(p_adj_bh)
  
  write.csv(reg_summary, file.path(TABLE_DIR, paste0(prefix, "_regression_summary.csv")), row.names = FALSE)
  
  e1_summary <- e1 %>%
    dplyr::mutate(
      dag_version = paste0(prefix, "_with_age_sex"),
      from_role   = dplyr::case_when(from %in% confounders ~ "Confounder",
                                     from %in% sig_vars    ~ "Variable", TRUE ~ "Outcome"),
      to_role     = dplyr::case_when(to   %in% confounders ~ "Confounder",
                                     to   %in% sig_vars    ~ "Variable", TRUE ~ "Outcome")
    )
  
  e2_summary <- e2 %>%
    dplyr::mutate(
      dag_version = paste0(prefix, "_without_age_sex"),
      from_role   = ifelse(from %in% sig_vars, "Variable", "Outcome"),
      to_role     = ifelse(to   %in% sig_vars, "Variable", "Outcome")
    )
  
  write.csv(e1_summary, file.path(TABLE_DIR, paste0(prefix, "_edges_with_age_sex.csv")),    row.names = FALSE)
  write.csv(e2_summary, file.path(TABLE_DIR, paste0(prefix, "_edges_without_age_sex.csv")), row.names = FALSE)
  
  cat("  [tables saved]", prefix, "\n")
}

# LASSO model 1

lasso_m1 <- read.csv(
  "../../4_Stability_Selection_LASSO/outputs/tables/stable_predictors_model1_all_vars.csv",
  stringsAsFactors = FALSE
)
col_m1 <- intersect(c("predictor", "predictors", "feature", "variable"), names(lasso_m1))[1]
if (is.na(col_m1)) stop("No predictor column in LASSO model1 file.")

run_dag(
  selected_vars_raw = lasso_m1[[col_m1]],
  ukb        = ukb,
  confounders = c("age_at_recruitment", "sex"),
  outcome     = "cvd",
  prefix      = "lasso_model1",
  label       = "LASSO model 1 (all vars)"
)

# LASSO model 2

lasso_m2 <- read.csv(
  "../../4_Stability_Selection_LASSO/outputs/tables/stable_predictors_model2_no_age_sysbp.csv",
  stringsAsFactors = FALSE
)
col_m2 <- intersect(c("predictor", "predictors", "feature", "variable"), names(lasso_m2))[1]
if (is.na(col_m2)) stop("No predictor column in LASSO model2 file.")

run_dag(
  selected_vars_raw = lasso_m2[[col_m2]],
  ukb        = ukb,
  confounders = c("age_at_recruitment", "sex"),
  outcome     = "cvd",
  prefix      = "lasso_model2",
  label       = "LASSO model 2 (no age/sysbp)"
)

# XGBoost model 1 

xgb_m1 <- read.csv(
  "../../5_Xgboost/outputs/stable_predictors_model1_all_vars_xgb_importance_nonzero_ranked.csv",
  stringsAsFactors = FALSE
)
col_xgb1 <- intersect(c("feature", "features", "variable", "predictor"), names(xgb_m1))[1]
if (is.na(col_xgb1)) stop("No feature column in XGBoost model1 file.")

run_dag(
  selected_vars_raw = xgb_m1[[col_xgb1]],
  ukb        = ukb,
  confounders = c("age_at_recruitment", "sex"),
  outcome     = "cvd",
  prefix      = "xgboost_model1",
  label       = "XGBoost model 1 (all vars)"
)

# XGBoost model 2

xgb_m2 <- read.csv(
  "../../5_Xgboost/outputs/stable_predictors_model2_no_age_sysbp_xgb_importance_nonzero_ranked.csv",
  stringsAsFactors = FALSE
)
col_xgb2 <- intersect(c("feature", "features", "variable", "predictor"), names(xgb_m2))[1]
if (is.na(col_xgb2)) stop("No feature column in XGBoost model2 file.")

run_dag(
  selected_vars_raw = xgb_m2[[col_xgb2]],
  ukb        = ukb,
  confounders = c("age_at_recruitment", "sex"),
  outcome     = "cvd",
  prefix      = "xgboost_model2",
  label       = "XGBoost model 2 (no age/sysbp)"
)

# file saved of manifest
all_files <- list.files("../outputs", recursive = TRUE, full.names = TRUE)
writeLines(all_files, file.path(TABLE_DIR, "saved_files_manifest.txt"))
cat("\nTotal files:", length(all_files), "\n")