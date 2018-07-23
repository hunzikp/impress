#!/usr/bin/env Rscript
args = commandArgs(trailingOnly=TRUE)

##########################################################
# Reddit EP Downloader Command Line Script
#   - Downloads newest EP threads
#   - Geolocates them
#   - Pushes meta-data to PostgreSQL DB
#   - Saves image
#
#
# COMMAND LINE ARGUMENTS
# [1] MODE (character)
#     Reddit access type; one of['new', 'top', or 'stream']
# 
# [2] NSUB (intgeger)
#     Number of submissions to process. Max 1000.
#
#
# EXTERNAL DEPENDENCIES 
# * Assumes that local elasticsearch engine (> 6.2) with indices
#   built by prepare_geoparse.R is accessible with default parameters.
# * Assumes local PostgreSQL database (> 9.0) with dbname 'impress'.
# * Assumes Python 3.6 installed and pip package 'praw' installed.
##########################################################

##############################
# Get command line args
##############################

if (length(args) == 0) {
  stop("No mode specified.", call.=FALSE)
} else if (length(args) == 1) {
  MODE = args[1]
  NSUB = 100
} else if (length(args) == 2) {
  MODE = args[1]
  NSUB = as.integer(args[2])
  if (is.na(NSUB)) {
    stop("Invalid NSUB argument.", call.=FALSE)
  }
}

##############################
# Dependencies & Connection Settings
##############################

library(tools)

## Prepare reticulate / Praw
library(reticulate)
reticulate::use_condaenv("py36")
praw <- reticulate::import("praw")

## Load functions for geparsing (also connects to local elastic search engine)
source('geoparse_functions.R')

## Connect to PostgreSQL DB
library(RPostgreSQL)
con <- dbConnect(dbDriver("PostgreSQL"), dbname = "impress",
                 host = "localhost", port = 5432,
                 user = "hunzikp", password = "gotthard")

##############################
# Prepare the DB
##############################

## Check whether earthporn table exists, if not -> create
exists <- dbExistsTable(con, 'earthporn')
if (!exists) {
  
  maketable_query <- "
  CREATE TABLE earthporn (
  ID CHAR(50) PRIMARY KEY,
  TITLE TEXT,
  CREATED_DATE timestamp, 
  URL TEXT,
  SCORE INT,
  NUM_COMMENTS INT,
  COUNTRY_NAME TEXT,
  ADMIN1_NAME TEXT,
  LOCATION_NAME TEXT,
  LAT REAL,
  LON REAL, 
  HAS_IMAGE BOOL,
  IMAGE_FILEPATH TEXT,
  CHECKED_DATE timestamp
  );"
  res <- dbSendQuery(con, maketable_query)
}

##############################
# Prepare the target directory
##############################

target_dir_path <- file.path("..", "earthporn")
if (!dir.exists(target_dir_path)) {
  dir.create(target_dir_path)
}


##############################
# Connection to Reddit
##############################

reddit = praw$Reddit(client_id='BB5kAYK1IyBnrQ',
                     client_secret='bnfMwZnq0hB22DLmgit-muJDxSI',
                     user_agent='impress_ep',
                     username='spikeandslab',
                     password='teilchen')
subreddit = reddit$subreddit('earthporn')


##############################
# Function for processing a submission
##############################

process_submission <- function(submission) {
  
  ## Timestamp
  checked_date <- as.POSIXct(Sys.time())
  
  ## Get submission info
  id <- submission$id
  title <- submission$title
  created_date <- as.POSIXct(submission$created_utc, origin="1970-01-01")
  url <- submission$url
  score <- submission$score
  num_comments <- submission$num_comments
  
  cat("SUBMISSION ", id, "\n")
  
  ## Check whether we've archived submission before
  statement <- paste0("SELECT * FROM earthporn WHERE id = '", id, "';")
  res.df <- dbFetch(dbSendQuery(con, statement))
  if (nrow(res.df) > 0) {
    cat("Submission already archived.\n")
    return(NULL)
  }
  
  ## Check whether there's an image; if so, get it
  has_image <- grepl("\\.jpg$", url) | grepl("\\.jpeg$", url)| grepl("\\.png$", url)
  image_filepath = NA
  if (has_image) {
    extension <- file_ext(url)
    filename <- paste0(id, '.', extension)
    image_filepath <- file.path("..", "earthporn", filename)
    tr <- try(download.file(url, destfile = image_filepath, quiet = TRUE), silent = TRUE)
    
    if ("try-error" %in% class(tr)) {
      cat("Image download failed.\n")
      has_image <- FALSE
      image_filepath <- NA
    }
    
    cat("Downloaded image.\n")
  } else {
    cat("No image found.\n")
  }
  
  ## Geoparse the title
  country_name <- NA
  admin1_name <- NA
  location_name <- NA
  lat <- NA
  lon <- NA
  # Get location string
  location_string <- get_capitalized_sequences(title)
  if (length(location_string) > 0) {
    location_string <- location_string[which.max(nchar(location_string))]
    
    # Remove 'OC' token from location_string
    location_string <- gsub(pattern = 'OC', replacement = '', x = location_string)
    
    # Determine location
    location.df <- detect_geolocation(location_string)
    
    # Get geo data
    location.df <- location.df[which.max(location.df$score),]  # Use best score
    country_name <- as.character(location.df$country_name)
    admin1_name <- as.character(location.df$admin1_name)
    location_name <- as.character(location.df$location_name)
    lat <- as.numeric(location.df$latitude)
    lon <- as.numeric(location.df$longitude)
    
    # Remove zero-length values
    rem_zlv <- function(x) {if (length(x) == 0) NA else x}
    country_name <- rem_zlv(country_name)
    admin1_name <- rem_zlv(admin1_name)
    location_name <- rem_zlv(location_name)
    lat <- rem_zlv(lat)
    lon <- rem_zlv(lon)
    
    cat("Geoparsing complete.\n")
  }
  
  ## Build data frame, upload to DB
  sub.df <- data.frame(id = id,
                       title = title,
                       created_date = created_date, 
                       url = url,
                       score = score, 
                       num_comments = num_comments,
                       country_name = country_name, 
                       admin1_name = admin1_name, 
                       location_name = location_name,
                       lat = lat, 
                       lon = lon,
                       has_image = has_image,
                       image_filepath = image_filepath,
                       checked_date = checked_date)
  dbWriteTable(con, "earthporn", sub.df, append = TRUE, row.names = FALSE)
  
  ## Check whether we need to end stream
  if (MODE == 'stream') {
    n_processed <<- n_processed + 1
    cat("Stream processed", n_processed, '.\n')
    if (n_processed >= NSUB) {
      stop("Stream processing done.", call.=FALSE)
    }
  }
  
  cat("Processing complete.\n \n")
}


##############################
# Process Submissions
##############################

if (MODE == 'new') {
  
  ## Porcess the newest 1000 submissions
  new_submissions = subreddit$new(limit = NSUB)
  res <- iterate(new_submissions, f = process_submission)
  
} else if (MODE == 'top') {
  
  ## Process the top 1000 submissions
  new_submissions = subreddit$top(limit = NSUB)
  res <- iterate(new_submissions, f = process_submission)
  
} else if (MODE == 'stream') {
  
  ## Stream processing
  n_processed <- 0
  subreddit_stream <- subreddit$stream$submissions()
  res <- iterate(subreddit_stream, f = process_submission)
}
