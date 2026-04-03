options(repos = c(CRAN = "https://cloud.r-project.org"))

# 1. Install missing packages
install.packages('fake')
install.packages("missForestPredict")
install.packages("sharp")

# 2. Load packages
library(missForestPredict)
library(pROC)
library(fake)
library(sharp)

cat("All packages loaded successfully\n")

