if (!interactive()) {
  setwd(dirname(normalizePath(commandArgs(trailingOnly=FALSE)[grep("--file=",commandArgs(trailingOnly=FALSE))][1] |> sub("--file=","",x=_))))
}
if (interactive()) {
  setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
}

library(dplyr)

# paths
RECODED_PATH   <- "../outputs/recoded.rds"
CVD_PATH       <- "/rds/general/user/aq25/projects/hda_25-26/live/TDS/General/Data/cvd_events.rds"
OUTPUT_DIR     <- "../../1_recoding_extraction_preprocessing/outputs"

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# load recoded data
recoded <- readRDS(RECODED_PATH)
recoded$eid <- rownames(recoded)
rownames(recoded) <- NULL
recoded <- recoded[, c("eid", setdiff(names(recoded), "eid"))]

cat("Recoded rows:", nrow(recoded), "\n")

# load and clean cvd events
cvd_events <- readRDS(CVD_PATH)
names(cvd_events)[names(cvd_events) == "date"] <- "cvd_date"
cvd_events$cvd_date <- as.Date(cvd_events$cvd_date)

# keep first cvd event per person
cvd_events <- cvd_events %>%
  arrange(eid, cvd_date) %>%
  distinct(eid, .keep_all = TRUE)

cat("CVD events:", nrow(cvd_events), "\n")
cat("Duplicate eids in cvd:", any(duplicated(cvd_events$eid)), "\n")

# merge and create binary cvd outcome
raw_data <- recoded %>%
  left_join(cvd_events %>% select(eid, cvd_date), by = "eid") %>%
  mutate(cvd = ifelse(is.na(cvd_date), 0, 1)) %>%
  relocate(cvd,      .after = eid) %>%
  relocate(cvd_date, .after = cvd)

# sanity checks
cat("CVD=0:", sum(raw_data$cvd == 0), "| CVD=1:", sum(raw_data$cvd == 1), "\n")
cat("Total rows:", nrow(raw_data), "\n")

# save
saveRDS(raw_data, file.path(OUTPUT_DIR, "ukb_raw.rds"))
cat("Saved: ukb_raw.rds\n")