# Recoding extracted categorical/continuous variables.
# Required inputs: outputs from 02-extract_selected.R

library(openxlsx)

# Loading outputs from previous steps
choices <- readRDS("../outputs/annot.rds")
mydata <- readRDS("../outputs/ukb_extracted.rds")

# Initialising objects
weird_recoding <- NULL
recoded_data <- mydata

# For loop over extracted columns
pb <- utils::txtProgressBar(style = 3)
for (k in 1:ncol(mydata)) {
  # Identifying corresponding coding name and encoding ID
  tmp_coding_name <- gsub("\\..*", "", colnames(mydata)[k])
  tmp_encoding_id <- choices[tmp_coding_name, "Coding"]
  
  if (!is.na(tmp_encoding_id)) {
    # Extracting corresponding encoding (if any)
    encoding <- read.table(paste0("../parameters/codings/codes_", tmp_encoding_id, ".txt"), header = TRUE, stringsAsFactors = FALSE)
    encoding$RecodedValue[encoding$RecodedValue == "NA"] <- NA
    encoding$RecodedMeaning[encoding$RecodedMeaning == "NA"] <- NA
    
    # Storing IDs of categorical variables for which some categories are not coded
    if (grepl("categorical", tolower(choices[tmp_coding_name, "ValueType"]))) {
      if (!all(as.character(na.exclude(mydata[, k])) %in% encoding$OriginalValue)) {
        print(all(as.character(na.exclude(mydata[, k])) %in% encoding$OriginalValue))
        weird_recoding <- c(weird_recoding, k)
      }
    }
    
    # Preparing recoding (applicable to any data type if a encoding ID is provided)
    recoding <- encoding$RecodedMeaning
    names(recoding) <- encoding$OriginalValue
    recoded_data[, k] <- recoding[as.character(mydata[, k])]
    
    if (grepl("categorical", tolower(choices[tmp_coding_name, "ValueType"]))) {
      # Recoding for categorical variables: levels are ordered as indicated by RecodedValue
      recoded_data[, k] <- factor(recoded_data[, k], levels = unique(encoding$RecodedMeaning[sort.list(as.numeric(encoding$RecodedValue))]))
    }
  }
  
  if ((grepl("integer", tolower(choices[tmp_coding_name, "ValueType"]))) | (grepl("continuous", tolower(choices[tmp_coding_name, "ValueType"])))) {
    # Recoding for continuous/integers: as numeric if no character strings
    if (all(!grepl("\\D", recoded_data[, k]))) {
      recoded_data[, k] <- as.numeric(recoded_data[, k])
    } else {
      recoded_data[, k] <- ifelse(mydata[, k] %in% names(recoding), recoded_data[, k], mydata[, k])
    }
  }
  
  if (grepl("date", tolower(choices[tmp_coding_name, "ValueType"]))) {
    # Recoding for dates
    recoded_data[, k] <- as.Date(recoded_data[, k], origin = "1970-01-01")
  }
  
  if (tolower(choices[tmp_coding_name, "ValueType"]) %in% c("time", "text", "compound")) {
    # Recoding for text/time/compound (rare types)
    recoded_data[, k] <- as.character(recoded_data[, k])
  }
  utils::setTxtProgressBar(pb, k / ncol(mydata))
}
cat("\n")
mydata <- recoded_data

# Quality check
if (length(weird_recoding) > 0) {
  print(paste0("Categories not described for ", length(weird_recoding), " fields:"))
  print(colnames(mydata)[weird_recoding])
}

# Additional recoding of continuous variables
continuous_encodings <- list.files(path = "../parameters/codings", pattern = "codes_field")
if (length(continuous_encodings) > 0) {
  print(paste0("Detected ", length(continuous_encodings), " coding(s) for continuous variables:"))
  print(cbind(continuous_encodings))
  
  # For loop over fields to recode
  fields_to_recode <- gsub("\\..*", "", gsub(".*_", "", continuous_encodings))
  for (i in length(fields_to_recode)) {
    tmp_coding_name <- choices[which(choices$FieldID == fields_to_recode[i]), "CodingName"]
    coding <- read.table(paste0("../parameters/codings/", continuous_encodings[i]),
                         header = TRUE, stringsAsFactors = FALSE
    )
    ids <- which(gsub("\\..*", "", colnames(mydata)) == tmp_coding_name)
    recoded_data <- cbind(recoded_data, recoded_data[, ids, drop = FALSE])
    colnames(recoded_data)[(ncol(recoded_data) - length(ids) + 1):ncol(recoded_data)] <- sapply(strsplit(colnames(recoded_data), split = "\\."), FUN = function(x) {
      paste0(x[1], "_continuous", ".", x[2], ".", x[3])
    })[ids]
    for (j in ids) {
      # Allowing for NA in min/max (replacing them by actual min/max
      tmp_encoding <- encoding
      tmp_encoding$MinValue[is.na(tmp_encoding$MinValue)] <- min(mydata[, j], na.rm = TRUE) - 1
      tmp_encoding$MaxValue[is.na(tmp_encoding$MaxValue)] <- max(mydata[, j], na.rm = TRUE) + 1
      
      # Recoding each category
      for (k in 1:nrow(tmp_encoding)) {
        tmp_cat_ids <- which((mydata[, j] >= tmp_encoding[k, "MinValue"]) & (mydata[, j] < tmp_encoding[k, "MaxValue"]))
        recoded_data[tmp_cat_ids, j] <- tmp_encoding[k, "RecodedMeaning"]
      }
      
      # Factor levels are ordered as indicated by RecodedValue
      recoded_data[, j] <- factor(recoded_data[, j], levels = tmp_encoding$RecodedMeaning[sort.list(as.numeric(tmp_encoding$RecodedValue))])
      
      # Quality check
      print(colnames(mydata)[j])
      print(table(recoded_data[, j]))
    }
  }
}
mydata <- recoded_data

# Including ArrayList and ArrayMethod for selection at next step
choices$ArrayList <- rep(NA, nrow(choices))
choices$ArrayMethod <- rep(0, nrow(choices))

# Extracting available arrays
for (k in 1:nrow(choices)) {
  ids <- which(gsub("\\..*", "", colnames(mydata)) == choices$CodingName[k])
  choices[k, "ArrayList"] <- paste(unique(gsub(".*\\.", "", colnames(mydata)[ids])), collapse = ",")
}

# Preparing additional column information
write.xlsx(choices, "../parameters/parameters.xlsx")

# Saving extracted dataset
saveRDS(mydata, "../outputs/recoded.rds")