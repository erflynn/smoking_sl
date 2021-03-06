# 01a_ae_part1_extract.R 
# 9/8/2020
# Code for extracting and combining the covariate data 
#
# Note - this is deprecated and needs to be redone with newer type of AE processing
#  (also make sure to dedup the study lists!)
# The code to process the individual files is included in the old sandbox files,
# this primarily combines and fixes minor inconsistencies across them. 
#
# Key processing TODOs:
#   - double check metadata processing 
# - lit comparison!!
#   - look into DGM IDs / repeated samples more
# - fill in missing expression sex labels



require('tidyverse')
require('googlesheets4')
require('googledrive')
require('lubridate')
require('GEOquery')

#### Read in all the covariate data

# NOTE: downloaded all of this from the google drive
list_cleaned <- list.files("data/cleaned_covariates/") %>% str_replace_all( ".csv", "")
my_sheets <- lapply(list_cleaned, function(my_f){
  read_csv(sprintf("data/cleaned_covariates/%s.csv", my_f))
})
names(my_sheets) <- list_cleaned

# what is overlapping: looks like 959 unique samples (by name) across 1811 total from 10 studies
list_acc <- lapply(my_sheets, function(x) x$geo_accession)
length(unlist(list_acc)) # 1811
length(unique(unlist(list_acc))) # 959

# get the columns that we'll have to normalize
list_cols <- lapply(my_sheets, function(x) colnames(x))
unique(unlist(list_cols))
table(unlist(list_cols))


#### Clean up the individual datasets
#This redos some of the normalization, fixes small errors in other columns, and renames columns so we can combine them later.

#TODO: 
# - compare w lit, esp w table 1
#- redo some more of these just as a sanity check
#- is there more pack-years info?
#  - consider fixing source-name to be more informative
#- some of these are trachea, etc

# --- reformat/fix values --- #
# gse108134$characteristics_ch1 --> take out copd
#   fix gse63127$copd
my_sheets$gse108134$copd <- str_detect(my_sheets$gse108134$characteristics_ch1, "COPD")
my_sheets$gse108134 <- my_sheets$gse108134 %>%
  mutate(copd=ifelse(copd, "y", "n")) %>%
  select(-characteristics_ch1)

my_sheets$gse63127 <- my_sheets$gse63127 %>%
  mutate(copd=ifelse(is.na(copd), NA, "y"))

# --- Rename --- #
# gse19667,gse63127$source_name_ch1 --> source_name
# gse108134$description --> dgm_id
# gse63127$"department of genetic medicine id:ch1" --> dgm_id
# gse108134$"30-day mean pm2.5 exposure level:ch1" --> pm2.5
# gse108134$"time of serial bronchoscopy (month):ch1" --> month

my_sheets$gse108134 <- my_sheets$gse108134 %>% 
  rename(
    dgm_id=description,
    pm2.5="30-day mean pm2.5 exposure level:ch1",
    month="time of serial bronchoscopy (month):ch1"
  )

my_sheets$gse19667 <- my_sheets$gse19667 %>% 
  rename(source_name=source_name_ch1)
my_sheets$gse63127 <- my_sheets$gse63127 %>% 
  rename(source_name=source_name_ch1, 
         dgm_id="department of genetic medicine id:ch1" )


# --- GSE64614 --- #
gse <- GEOquery::getGEO("GSE64614") 
pDat <- pData(gse$GSE64614_series_matrix.txt.gz) 

dgm_dat <- pDat %>% 
  select(geo_accession, `department of genetic medicine id:ch1`) %>%
  rename(dgm_id=`department of genetic medicine id:ch1`)
gse64614_fix <- left_join(my_sheets$gse64614, dgm_dat, by="geo_accession")
gse64614_fix2 <- gse64614_fix %>% 
  mutate(
    copd=ifelse(smok=="COPD", "y", copd),
    smok=ifelse(smok=="COPD", NA, smok),
    ethnic=case_when(ethnic=="Afr" ~ "black",
                     ethnic=="Eur" ~ "white", 
                     TRUE ~ ethnic),
    smok=case_when(smok=="nonsmoker"~ "NS",
                   smok=="smoker" ~ "S",
                   TRUE ~ smok)
  ) 

my_sheets$gse64614 <- gse64614_fix2 


# --- GSE19667 --- #
gse2 <- getGEO("GSE19667")
pDat2 <- pData(gse2$GSE19667_series_matrix.txt.gz) 
gse19667_fix <- pDat2 %>% 
  unite("sex", c(`sex:ch1`, `Sex:ch1`), sep=";", na.rm=TRUE) %>%
  unite("ethnic", c("ethnic group:ch1", "Ethnic group:ch1"), sep=";", na.rm=TRUE) %>%
  unite("smok", c("smoking status:ch1", "Smoking status:ch1"), sep=";", na.rm=TRUE) %>%
  unite("age", c("age:ch1", "Age:ch1"), sep=";", na.rm=TRUE)
# source_name, description, title - theyre all small airways, description is sometimes empty
# title appears to have the ID
gse19667_fix2 <- gse19667_fix %>%
  select(geo_accession, source_name_ch1, title, sex, ethnic, smok, age) %>%
  mutate(pack_years=str_extract(smok,"[0-9|\\.]+"),
         smok=case_when(str_detect(smok, "non-smoker") ~ "NS",
                        str_detect(smok, "smoker") ~ "S",
                        TRUE ~ smok),
         dgm_id=str_extract(title,"[0-9]+")) %>%
  select(-title) %>%
  rename(source_name=source_name_ch1)

my_sheets$gse19667 <- gse19667_fix2 


# --- GSE19407 --- #
gse3 <- getGEO("GSE19407")
pData3 <- pData(gse3$GSE19407_series_matrix.txt.gz)
gse19407_fix <- pData3 %>% unite("sex", c(`sex:ch1`, `Sex:ch1`), sep=";", na.rm=TRUE) %>%
  unite("ethnic", c("ethnic group:ch1", "Ethnic group:ch1"), sep=";", na.rm=TRUE) %>%
  unite("smok", c("smoking status:ch1", "Smoking Status:ch1", "Smoking status:ch1"), sep=";", na.rm=TRUE) %>%
  unite("age", c("age:ch1", "Age:ch1"), sep=";", na.rm=TRUE)

gse19407_fix2 <- gse19407_fix %>%
  select(geo_accession, source_name_ch1, title, sex, ethnic, smok, age) %>%
  mutate(pack_years=str_extract(smok,"[0-9|\\.]+"),
         smok=case_when(str_detect(smok, "non-smoker") ~ "NS",
                        str_detect(smok, "smoker|pack-years") ~ "S",
                        TRUE ~ smok),
         copd=ifelse(str_detect(title, "COPD"), "y", NA),
         dgm_id=str_extract(title,"[0-9]+")) %>%
  select(-title) %>%
  rename(source_name=source_name_ch1)

my_sheets$gse19407 <- gse19407_fix2 



#### Put data together

list_cols <- lapply(my_sheets, function(x) colnames(x))
all_cols <- setdiff(names(sort(desc(table(unlist(list_cols))))), "X1")

# -- fill in missing columns -- #
add_missing_cols <- function(sheet, study_name){
  missing_cols <- setdiff(all_cols, colnames(sheet))
  for (new_col in missing_cols){
    sheet[,new_col] <- NA
  }
  sheet$study <- study_name
  return(sheet %>% select(study, all_cols))
}

reform_sheets <- lapply(1:length(my_sheets), function(i) add_missing_cols(my_sheets[[i]], names(my_sheets)[[i]]))

# -- put together -- #
sheets_comb <- do.call(rbind, reform_sheets)

collapse_id <- function(x) {
  ifelse(all(is.na(x)), NA, 
         paste(unique(x[!is.na(x)]), collapse=";"))
}

# -- condense by ID -- #
# this means there is one row per sample
sheets_comb2 <- sheets_comb %>% 
  group_by(geo_accession) %>%
  mutate_all(~collapse_id(.)) %>%
  unique() %>%
  ungroup()

# it is COPD if any is COPD
sheets_comb3 <- sheets_comb2 %>% 
  mutate(copd=ifelse(copd=="n;y", "y", copd))



#### Get date information to try to figure out study membership
# -- download the data w/ GEOquery -- #
gse.list <- sapply(list_cleaned, toupper)
gses <- lapply(gse.list, getGEO) 
lapply(gses, function(x) x[[1]]@annotation) # all GPL570

# -- each sample HAS a submission date -- #
submission_dates <- do.call(rbind, lapply(gses, function(x) pData(x[[1]])[,c("geo_accession", "submission_date")]))

gsm_to_date <- submission_dates %>% 
  group_by(geo_accession) %>%
  summarize(submission_date=collapse_id(submission_date))

# -- each study also has a submission date -- #
study_dates <- do.call(rbind, lapply(gses, function(x) experimentData(x[[1]])@other[c("geo_accession", "submission_date")])) %>% 
  as.data.frame() %>% 
  rename(study=geo_accession, study_date=submission_date) %>%
  mutate(study=as.character(study),
         study_date=mdy(as.character(study_date))) %>%
  arrange(study_date)

# -- add the sameple submission date
sheets_comb4 <- sheets_comb3 %>% 
  left_join(gsm_to_date) %>%
  mutate(submission_date=mdy(submission_date))

unique(sheets_comb4$submission_date)[order(unique(sheets_comb4$submission_date))] # there are *TWENTY-SIX* dates

# -- try assigning each to the earliest study date
sample_to_study <- sheets_comb4 %>% 
  select(study, geo_accession, submission_date) %>% 
  separate_rows(study, sep=";") %>%
  mutate(study=toupper(study)) %>%
  left_join(study_dates) %>%
  arrange(geo_accession, study_date) %>%
  group_by(geo_accession) %>%
  mutate(idx=n():1) %>%
  top_n(1) %>%
  ungroup()

# look at the study/sample breakdown
sample_to_study %>% group_by(study) %>% count()

# add in a column for study info
sheets_comb5 <- sheets_comb4 %>%
  left_join(sample_to_study %>% 
              select(study, geo_accession) %>% 
              unique() %>% 
              rename(first_study=study))


# add the study date information
sheets_comb6 <- sheets_comb5 %>%
  left_join(study_dates, by=c("first_study"="study")) %>%
  arrange(study_date) %>%
  mutate(study_year=year(study_date)) %>%
  # bin by year but put 2009/2010 together
  mutate(year_bin=ifelse(study_year==2010, 2009, study_year)) %>%
  select(-study_year) %>%
  mutate(study=toupper(study)) %>%
  rename(metadata_sex=sex,
         race_ethnicity=ethnic)

stopifnot(nrow(sheets_comb6)==nrow(sheets_comb2))




#### Add in our sex labels
#TODO: try to rescue the missing sex labels (94 samples!) -- unclear why, make sure we have a reason for each!

sl_sample <- googlesheets4::read_sheet("https://docs.google.com/spreadsheets/d/1lEUVsyXLDcyUQB7mXk0B-LtsWkBn66gKaIV74OFAGVs/edit#gid=463642465")

# add this to the data we have 
sl_compare <- sl_sample %>% 
  select(sample_acc, pred, expr_sex, text_sex) %>% 
  rename(geo_accession=sample_acc) %>%
  unique() %>%
  right_join(sheets_comb6 %>% 
               select(geo_accession, metadata_sex)) %>%
  mutate(metadata_sex=case_when(
    is.na(metadata_sex) ~ "unknown",
    metadata_sex=="M" ~ "male", 
    metadata_sex=="F" ~ "female"
  )) %>%
  mutate(expr_sex=ifelse(is.na(expr_sex), "unknown", expr_sex)) %>%
  select(-text_sex)

## only 4 switch labels and these are high-confidence
#sl_compare %>% 
#  group_by(expr_sex, metadata_sex) %>% count()
#sl_compare %>% filter(expr_sex=="female" & metadata_sex=="male") 
# add a column with sex labels
sheets_comb7 <- sheets_comb6 %>% 
  left_join(sl_compare %>% 
              select(geo_accession, expr_sex) %>% 
              unique()) 




#### Descriptive: repeated samples 
#We are doing this using DGM ID. There are often multiple samples from the same subject, we want to make sure we are aware of this and when this occurs within and between studies. We may want to condense the data using this, but I have not done this yet. This is just descriptive.

#TODOs: 
#  - figure out what is going on with the non DGM prefix IDs
#- decide how to condense


# check - how many repeats are there?
# 192 DGM_IDs are repeated
sheets_comb7 %>% 
  filter(!is.na(dgm_id)) %>% 
  group_by(dgm_id) %>% 
  count() %>% 
  filter(n>1) %>% 
  arrange(desc(n)) %>% 
  View() 

sheets_comb7 %>% 
  group_by(dgm_id) %>% 
  count() %>% 
  filter(n==1 | is.na(dgm_id)) %>% 
  ungroup() %>% 
  summarize(tot=sum(n)) # 476  (217 are NAs)

# try grouping by dgm_id
condensed <- sheets_comb7 %>% filter(!is.na(dgm_id)) %>% 
  group_by(dgm_id) %>%
  mutate_all(~collapse_id(.)) %>%
  unique()
# this is puzzling -- there is a lot of label switching...

# try grouping by dgm_id *ONLY* using the ones with the
#  DGM prefix (it is possible the others are different)
condensed_dgm <- sheets_comb7 %>% 
  filter(str_detect(dgm_id, "DGM")) %>%
  group_by(dgm_id) %>%
  mutate_all(~collapse_id(.)) %>%
  unique()
# no label switching



#### Write out the data

write_csv(sheets_comb7, "data/sae_sl_mapped.csv")


