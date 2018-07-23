
##########################################################
# Prepare impress image/metadata dataset 
#   - Clean data
#       -> remove missing/corrupt image sumbionssions
#       -> remove submissions without geo-tag
#   - Resize images
#       -> Standardize image sizes
##########################################################

##############################
# Constants
##############################

IMAGE_SIZE <- 512  # target size of resized images

##############################
# Dependencies & Connection Settings
##############################

library(imager)

## Connect to PostgreSQL DB
library(RPostgreSQL)
con <- dbConnect(dbDriver("PostgreSQL"), dbname = "impress",
                 host = "localhost", port = 5432,
                 user = "hunzikp", password = "gotthard")


##############################
# Get clean meta-data
# -> Only submissions with image
# -> Only submissions with geotag
##############################

raw_meta.df <- dbReadTable(con, "earthporn")
meta.df <- raw_meta.df[raw_meta.df$has_image,]
meta.df <- meta.df[!is.na(meta.df$lat) & !is.na(meta.df$lon),]


##############################
# Identify valid images, resize
# -> We use the imagemagick command line tool for both
##############################

meta.df$valid_image <- NA
meta.df$resize_image_filepath <- NA
for (i in 1:nrow(meta.df)) {
  
  image_filepath <- meta.df$image_filepath[i]
  a <- system(paste0("identify ", image_filepath), intern = TRUE, ignore.stderr = TRUE)
  
  if (length(a) == 0) {
    # Invalid image
    meta.df$valid_image[i] <- FALSE
    next
  }
  
  size_string <- paste0(IMAGE_SIZE, 'X', IMAGE_SIZE, '!')
  id <- gsub(" ", "", meta.df$id[i])
  resize_image_filepath <- file.path('data', paste0(id, ".jpg"))
  command <- paste0("convert -resize ", size_string, " ", image_filepath, " ", resize_image_filepath)
  system(command)
  meta.df$resize_image_filepath[i] <- resize_image_filepath
  meta.df$valid_image[i] <- TRUE
  
  print(i)
  flush.console()
}

##############################
# Save meta-data for valid images
##############################

meta.df <- meta.df[meta.df$valid_image,]
write.csv(meta.df, file = 'data/meta.csv', row.names = FALSE)

