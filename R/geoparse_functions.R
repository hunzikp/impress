##########################################################
# Functions for geo-parsing single-location strings
#
#
# EXTERNAL DEPENDENCIES 
# * Assumes that local elasticsearch engine (> 6.2) with indices
#   built by prepare_geoparse.R is accessible with default parameters.
##########################################################

################################################
# Dependencies / Options
################################################

library(elastic)
library(rjson)
library(tokenizers)
options(stringsAsFactors = FALSE)
elastic::connect()

################################################
# General purpose string functions
################################################

is_capitalized <- function(string) {
  1 %in% unlist(gregexpr("[A-Z]", string))
}

is_all_caps <- function(string) {
  string == toupper(string)
}

get_capitalized_sequences <- function(string, max_gap = 2) {
  
  sentences <- tokenize_sentences(string)[[1]]
  out <- c()
  for (sentence in sentences) {
    
    ## Make sequences of upper/lower case words; get rid of lowercase sequences with length <= max_gap
    tokens <- tokenize_ptb(sentence, lowercase = FALSE)[[1]]
    token_is_capitalized <- sapply(tokens, is_capitalized)
    sequences <- split(tokens, cumsum(c(1, abs(diff(token_is_capitalized)))))
    
    ## Remove gaps
    sequence_is_capitalized <- unlist(lapply(sequences, function(x) is_capitalized(x[1])))
    sequence_length <- unlist(lapply(sequences, length))
    short_lowercase_sequences <- which(!sequence_is_capitalized & sequence_length <= max_gap)
    if (length(short_lowercase_sequences) > 0) {
      sequences <- sequences[-short_lowercase_sequences]
    }
    
    ## Make new capitalized sequences without gap words
    tokens <- unlist(sequences)
    token_is_capitalized <- sapply(tokens, is_capitalized)
    sequences <- split(tokens, cumsum(c(1, abs(diff(token_is_capitalized)))))
    sequence_is_capitalized <- which(unlist(lapply(sequences, function(x) is_capitalized(x[1]))))
    capital_sequences <- sequences[sequence_is_capitalized]
    
    if (length(capital_sequences) > 0) {
      capital_sequences <- unlist(lapply(capital_sequences, function(x) paste(x, collapse = " ")))
      out <- c(out, capital_sequences) 
    }
  }
  
  return(out)
}

get_capitalized_ngrams <- function(string, n_size = 3) {
  
  out <- c()
  sentences <- tokenize_sentences(string)[[1]]
  for (sentence in sentences) {

    # Make Ngrams
    ngrams <- tokenize_ngrams(sentence, lowercase = FALSE, n = n_size)[[1]]
    
    # Only keep ngrams with at least one capitalized word
    capital_ngrams <- c()
    for (ngram in ngrams) {
      wrds <- tokenize_words(ngram, lowercase = FALSE)[[1]]
      has_capital <- any(sapply(wrds, is_capitalized))
      if (has_capital) {
        capital_ngrams <- c(capital_ngrams, ngram)
      }
    }

    out <- c(out, capital_ngrams)
  }
  
  return(out)
}


################################################
# Detect country name in string
################################################

detect_country <- function(location_string, top_n = 5) {
  
  ## Prepare data frame
  countries.df <- data.frame(country_name = character(), country_code = character(),
                             match_type = character(), score = numeric())
  
  ## 1: Try to find full, spelled-out country name
  lquery <- list("query" = list("match" = list(
    country_name = location_string
  )))
  jquery <- jsonlite::toJSON(lquery, pretty = TRUE, auto_unbox = TRUE)
  res <- Search(index="countries", body = jquery, size = top_n)
  if (res$hits$total > 0) {
    for (i in 1:length(res$hits$hits)) {
      new.df <- list(country_name = res$hits$hits[[i]]$`_source`$country_name, 
                           country_code = res$hits$hits[[i]]$`_source`$country_code, 
                           match_type = "full_text", 
                           score = res$hits$hits[[i]]$`_score`)
      new.df <- lapply(new.df, function(x) if (is.null(x)) {NA} else {x})
      countries.df <- rbind(countries.df, new.df)
    }
  }

  ## 2: Try to find country abbreviation
  tokens <- tokenize_words(location_string, lowercase = FALSE, strip_punct = TRUE)[[1]]
  allcaps <- sapply(tokens, is_all_caps)  # Abbrevs are all caps
  multichar <- sapply(tokens, function(x) nchar(x) > 1) # Abbrevs have more than 1 char
  is_abbrev <- allcaps & multichar
  
  if (any(is_abbrev)) {
    
    abbrevs <- tokens[is_abbrev]
    for (abb in abbrevs) {
      lquery <- list("query" = list("multi_match" = list(
        query = abb, 
        type = "best_fields", 
        fields = c("country_code", "country_code3"),
        operator = "and"
      )))
      jquery <- jsonlite::toJSON(lquery, pretty = TRUE, auto_unbox = TRUE)
      res <- Search(index="countries", body = jquery, size = top_n)
      if (res$hits$total > 0) {
        for (i in 1:length(res$hits$hits)) {
          new.df <- list(country_name = res$hits$hits[[i]]$`_source`$country_name, 
                               country_code = res$hits$hits[[i]]$`_source`$country_code, 
                               match_type = "abbreviation", 
                               score = res$hits$hits[[i]]$`_score`)
          new.df <- lapply(new.df, function(x) if (is.null(x)) {NA} else {x})
          countries.df <- rbind(countries.df, new.df)
        }
      }
    }
  }

  return(countries.df)
}


################################################
# Detect admin unit name in string
################################################

detect_admin_unit <- function(location_string, top_n = 5) {
  
  ## Prepare data frame
  admin.df <- data.frame(admin1_name = character(),
                         admin1_code = character(),
                         country_code = character(),
                         country_name = character(),
                         match_type = character(), 
                         score = numeric())
  
  ## 1: Try to find full, spelled-out country name
  lquery <- list("query" = list("match" = list(
    admin1_name = location_string
  )))
  jquery <- jsonlite::toJSON(lquery, pretty = TRUE, auto_unbox = TRUE)
  res <- Search(index="adminunits", body = jquery, size = top_n)
  if (res$hits$total > 0) {
    for (i in 1:length(res$hits$hits)) {
      new.df <- list(admin1_name = res$hits$hits[[i]]$`_source`$admin1_name, 
                           admin1_code = res$hits$hits[[i]]$`_source`$admin1_code, 
                           country_code = res$hits$hits[[i]]$`_source`$country_code,
                           country_name = res$hits$hits[[i]]$`_source`$country_name, 
                           match_type = "full_text", 
                           score = res$hits$hits[[i]]$`_score`)
      new.df <- lapply(new.df, function(x) if (is.null(x)) {NA} else {x})
      admin.df <- rbind(admin.df, new.df)
    }
  }
  
  ## 2: Try to find abbreviation
  tokens <- tokenize_words(location_string, lowercase = FALSE, strip_punct = TRUE)[[1]]
  allcaps <- sapply(tokens, is_all_caps)  # Abbrevs are all caps
  multichar <- sapply(tokens, function(x) nchar(x) > 1) # Abbrevs have more than 1 char
  is_abbrev <- allcaps & multichar
  
  if (any(is_abbrev)) {
    
    abbrevs <- tokens[is_abbrev]
    for (abb in abbrevs) {
      lquery <- list("query" = list("match" = list(
        admin1_code = abb
      )))
      jquery <- jsonlite::toJSON(lquery, pretty = TRUE, auto_unbox = TRUE)
      res <- Search(index="adminunits", body = jquery, size = top_n)
      if (res$hits$total > 0) {
        for (i in 1:length(res$hits$hits)) {
          new.df <- list(admin1_name = res$hits$hits[[i]]$`_source`$admin1_name, 
                               admin1_code = res$hits$hits[[i]]$`_source`$admin1_code, 
                               country_code = res$hits$hits[[i]]$`_source`$country_code,
                               country_name = res$hits$hits[[i]]$`_source`$country_name,
                               match_type = "abbreviation", 
                               score = res$hits$hits[[i]]$`_score`)
          new.df <- lapply(new.df, function(x) if (is.null(x)) {NA} else {x})
          admin.df <- rbind(admin.df, new.df)
        }
      }
    }
  }
  
  return(admin.df)
}


################################################
# Detect geolocation
################################################

detect_geolocation <- function(location_string, top_n = 5) {
  
  ## Prepare data frame
  geo.df <- data.frame(location_name = character(),
                       admin1_code = character(),
                       admin2_name = character(),
                       country_code = character(),
                       country_name = character(),
                       latitude = numeric(),
                       longitude = numeric(),
                       score = numeric())
  
  ## Multi-field search
  lquery <- list("query" = list("multi_match" = list(
    query = location_string, 
    type = "most_fields", 
    fields = c("asciiname", "admin1_name", "country_name", "admin1_code"),
    operator = "or"
  )))
  jquery <- jsonlite::toJSON(lquery, pretty = TRUE, auto_unbox = TRUE)
  res <- Search(index="geoparse", body = jquery, size = top_n)
  if (res$hits$total > 0) {
    for (i in 1:length(res$hits$hits)) {
      new.df <- list(location_name = res$hits$hits[[i]]$`_source`$name,
                           admin1_code = res$hits$hits[[i]]$`_source`$admin1_code, 
                           admin1_name = res$hits$hits[[i]]$`_source`$admin1_name, 
                           country_code = res$hits$hits[[i]]$`_source`$country_code, 
                           country_name = res$hits$hits[[i]]$`_source`$country_name, 
                           latitude = res$hits$hits[[i]]$`_source`$latitude,
                           longitude = res$hits$hits[[i]]$`_source`$longitude,
                           score = res$hits$hits[[i]]$`_score`)
      new.df <- lapply(new.df, function(x) if (is.null(x)) {NA} else {x})
      geo.df <- rbind(geo.df, new.df)
    }
  }

  return(geo.df)
}