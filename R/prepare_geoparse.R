
##########################################################
# Builds a geoparse index on a local elastic search engine
#
#
# EXTERNAL DEPENDENCIES 
# * Assumes that elasticsearch engine (> 6.2) is running
#   on localhost and accessible with default parameters.
##########################################################


################################################
# Dependencies
################################################

library(elastic)

################################################
# PREPARE & UPOAD GEONAMES DATA
################################################

## Set col names
nms <- c("geonameid", "name", "asciiname", "alternatenames", "latitude", "longitude", 
         "feature_class", "feature_code", "country_code", "cc2", "admin1_code", 
         "admin2_code", "admin3_code", "admin4_code", "population", "elevation", 
         "dem", "timezone", "modification_date")

## Get relevant directories
dirs <- list.dirs("geonames", recursive = FALSE)

## Iterate over dirs, get data
gn.df <- NULL
for (dir in dirs) {
  file_paths <- list.files(dir, full.names = TRUE)
  file_paths <- file_paths[!grepl("readme", file_paths)]
  this.df <- read.table(file_paths[1], fill=TRUE, header=FALSE, sep="\t", quote="", stringsAsFactors=FALSE)
  names(this.df) <- nms
  if (is.null(gn.df)) {
    gn.df <- this.df
  } else {
    gn.df <- rbind(gn.df, this.df)
  }
}

## Add country names
cntr.df <- read.table("geonames/countries.txt", fill = TRUE, header = TRUE, sep = "\t", quote = "", stringsAsFactors = FALSE)
cntr.df <- cntr.df[,c("ISO", "Country")]
names(cntr.df) <- c("country_code", "country_name")
gn.df <- merge(gn.df, cntr.df, by = "country_code", all.x = TRUE, all.y = FALSE, sort = FALSE)

## Add admin unit names
adm.df <- read.table("geonames/admin1CodesASCII.txt", fill = TRUE, header = FALSE, sep = "\t", quote = "", stringsAsFactors = FALSE)
nms <- c("adm1_code_ext", "admin1_name","ascii", "geonameid")
names(adm.df) <- nms
adm.df <- adm.df[,c("adm1_code_ext", "admin1_name")]
gn.df$adm1_code_ext <- paste(gn.df$country_code, gn.df$admin1_code, sep = ".")
gn.df <- merge(gn.df, adm.df, by = "adm1_code_ext", all.x = TRUE, all.y = FALSE, sort = FALSE)

## Limit to columns of interest
geoparse.df <- gn.df[,c("name", "asciiname", "alternatenames", "latitude", "longitude", "feature_class", 
                        "feature_code", "admin1_code", "admin1_name", 
                        "country_code", "country_name", "population", "elevation")]

## Connect to elastic
elastic::connect() # Default settings connect to elasticsearch running on localhost

## Bulk upload geonames table into new index
res <- invisible(docs_bulk(geoparse.df, "geoparse"))


################################################
# PREPARE & UPOAD COUNTRY DATA
################################################

cntr.df <- read.table("geonames/countries.txt", fill = TRUE, header = TRUE, sep = "\t", quote = "", stringsAsFactors = FALSE)
cntr.df <- cntr.df[,c("ISO", "ISO3", "Country", "Capital", "geonameid")]
names(cntr.df) <- c("country_code", "country_code3", "country_name", "capital_name", "geonameid")
res <- invisible(docs_bulk(cntr.df, "countries"))


################################################
# PREPARE & UPOAD ADMIN 1 DATA
################################################

adm.df <- read.table("geonames/admin1CodesASCII.txt", fill = TRUE, header = FALSE, sep = "\t", quote = "", stringsAsFactors = FALSE)
nms <- c("adm1_code_ext", "admin1_name", "ascii", "geonameid")
names(adm.df) <- nms
adm.df$admin1_code <- sapply(adm.df$adm1_code_ext, function(x) {strsplit(x, split = ".", fixed = TRUE)[[1]][2]})
adm.df$country_code <- sapply(adm.df$adm1_code_ext, function(x) {strsplit(x, split = ".", fixed = TRUE)[[1]][1]})
adm.df <- merge(adm.df, cntr.df[,c("country_code", "country_name")], by = "country_code", all.x = TRUE, all.y = FALSE)
res <- invisible(docs_bulk(adm.df, "adminunits"))




