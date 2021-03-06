# 03_clean_manual_annot.R
# 1/4/2020
# Read in results from manual annotation and clean up the results
#
# tables generated:
# - S1 (cleaned anntoations): "data/supp_tables/supp_table_1_annot.csv"
# intermediate files generated:
# - sex labels for smoking data: "data/smok_samples_w_sl.csv"
#
# note: treated cells are annotated DURING this execution:
#  treated_cls_to_annot_v2.csv


library(tidyverse)
library(googlesheets4)
RB.PATH <- "../drug_trt/data/"

isSuper <- function(s1.samples, s2.samples){
  # find which set is a super set of the other
  # returns: 0 (same), 1 (1> 2), 2 (2 > 1), or NA (neither)
  my_u <- union(s1.samples, s2.samples)
  my_int <- intersect(s1.samples, s2.samples)
  if (length(my_u)==length(my_int)){
    if(setdiff(my_u, my_int)==0){
      return(0)
    }
  }
  if (length(setdiff(s1.samples, s2.samples)) == 0){
    return(2)
  } 
  if (length(setdiff(s2.samples, s1.samples)) == 0){
    return(1)
  }
  
  return(NA)
}


# read in the manually annotated sheet I filled in
my_gs <- read_sheet("https://docs.google.com/spreadsheets/d/1VGK2xPXhQv1yReE701JhkVPKNkI7Wxh3XZ33RoNxowU/edit#gid=1179723923")

# 28 studies
super_series <- my_gs %>% 
  filter(str_detect(type, "SuperSeries")) %>% 
  pull(study_acc)
# grab the studies included in each
# - not easy to grab via GEOmetadb

# read in the study_sample mapping
exp_sample_map <- read_csv(sprintf("%s/01_sample_lists/rb_metadata/human_microarray_exp_to_sample.csv", RB.PATH)) %>%
  bind_rows(read_csv(sprintf("%s/01_sample_lists/rb_metadata/human_rnaseq_exp_to_sample.csv", RB.PATH)))

exp_sample_map2 <- exp_sample_map %>% semi_join(my_gs, by="study_acc") %>% distinct()
exp_sample_map2 %>% distinct(sample_acc) %>% filter(str_detect(sample_acc, "GSM")) %>% nrow() # 26045
exp_sample_map2 %>% distinct(sample_acc) %>% filter(str_detect(sample_acc, "ERR|SRR|DRR")) %>% nrow() # 3276
exp_sample_map2 %>% distinct(sample_acc) %>% filter(!str_detect(sample_acc, "ERR|SRR|DRR|GSM")) %>% nrow() # 149

exp_sample_map_c <- exp_sample_map2 %>% group_by(study_acc) %>% count()
exp_sample_map2 %>% filter(study_acc %in% super_series)

# deduplicate by membership
length(unique(exp_sample_map2$sample_acc)) # 29467 --> 34973

study_to_sample <- lapply(exp_sample_map2 %>% 
                            arrange(study_acc) %>%
                        group_split(study_acc), 
                        function(x) x %>% pull(sample_acc))
names(study_to_sample) <- unique(exp_sample_map2$study_acc)

# identify samples that are present in multiple studies
sample_to_study <- exp_sample_map2 %>% 
  arrange(sample_acc, study_acc) %>%
  group_by(sample_acc) %>%
  summarise(n=n(), study_acc=paste(study_acc, collapse=";"))

# get the list of all groups of overlap
distinct_study_strs <- lapply(sample_to_study %>% 
  filter(n>1) %>% 
  distinct(study_acc) %>% 
  mutate(str_id=1:n()) %>%
  group_split(str_id), 
  function(x) str_split(x %>% pull(study_acc), ";")[[1]]) # 171 grps


# go thru and identify supersets + remove their children
list_same <- list()
list_super <- list()
removed_gses <- c()
super_df <- tibble("super"=c(), "other"=c())
for (study_str in 1:length(distinct_study_strs)){
  list_comb <- distinct_study_strs[[study_str]]
  for (i in 1:(length(list_comb)-1)){
    if (list_comb[i] %in% removed_gses){
      print(sprintf("%s already removed", list_comb[i]))
      break 
    }
    for (j in (i+1):length(list_comb)){
      pair <- c(list_comb[i], list_comb[j])
      print(pair)
      id1 <- pair[[1]]
      id2 <- pair[[2]]
      if (id2 %in% removed_gses){
        print(sprintf("%s already removed", id2))
        break 
      }
      s1.samples <- study_to_sample[[id1]]
      s2.samples <- study_to_sample[[id2]]
      super <- isSuper(s1.samples, s2.samples) 
      if (is.na(super)){
        #print("no superset")
      } else {
        if (super == 0){
          #id.early <- getEarlierStudy(id1, id2)
          #id.other <- pair[pair!=id.early]
          print(sprintf(" %s and %s are the same", id1, id2))
          list_same <- append(list_same, c(id1, id2))
        }
        # keep the superset
        else {
          idsup <- pair[[super]]
          id.other <- pair[[-super]]
          print(sprintf(" %s is a superset of %s", idsup, id.other))
          super_df <- super_df %>% bind_rows(tibble("super"=idsup, "other"=id.other))
          removed_gses <- c(removed_gses, id.other)
        }
      }
    }
  }
}
# none are the same
# 45 are supersets of the others


# --- condense the superset data --- #
long_sup <- super_df %>% mutate(pair_id=super) %>%
  pivot_longer(c(super, other), names_to="study_type", values_to="study_acc")
long_sup2 <- long_sup %>% 
  left_join(my_gs, by="study_acc") %>%
  mutate(across(keep:smok_grps, ~ifelse(.=="NA", NA, .))) %>%
  group_by(pair_id) %>%
  mutate(keep=paste(unique(keep[!is.na(keep)]), collapse=";"),
         type=paste(unique(type[!is.na(type)]), collapse=";"),
         tissue2=paste(unique(tissue2[!is.na(tissue2)]), collapse=";"),
         description=paste(description, collapse=";"),
         treatment=paste(unique(treatment[!is.na(treatment)]), collapse=";"),
         studies=paste(study_acc[study_acc!=pair_id], collapse=";")) 

# double check these
long_sup2 %>% filter(str_detect(keep, ";"), !str_detect(keep, "yes"), study_type=="super")  
# GSE29007 --> keep

sup_studies_dedup <- long_sup2 %>% 
  mutate(keep=ifelse(study_acc=="GSE29007", "yes", keep)) %>%
  filter(study_type=="super") %>%
  ungroup() %>%
  select(-pair_id, -study_type) %>%
  distinct() %>%
  mutate(keep=ifelse(str_detect(keep,"yes"), "yes", keep),
         type=str_replace_all(type, "SuperSeries;", "")) %>%
  mutate(keep=str_replace_all(keep, "\\?\\?;", ""))
  
# --- put together --- #
completed_gs <- my_gs %>% 
  anti_join(long_sup %>% distinct(study_acc), by="study_acc") %>% 
  mutate(studies="") %>%
  bind_rows(sup_studies_dedup) %>%
  select(-"...12") 

# --- fix or fill in missing annotations --- #

completed_gs %>% filter(keep=="??")
# GSE69851 --> no, all nicotine, treated cells
# GSE61628 --> yes, smokers vs nonsmokers
# GSE33338 --> no, all smokers
completed_gs2 <- completed_gs %>%
  mutate(keep=case_when(
    study_acc=="GSE69851" ~ "no",
    study_acc=="GSE61628" ~ "yes",
    study_acc=="GSE33338" ~ "no",
    TRUE ~ keep
  ),  
  design=case_when(study_acc=="GSE69851" ~ "all nicotine", 
                   type == "all nicotine dependent" ~ type,
                   TRUE ~ design),
  type = case_when(
    study_acc=="GSE69851" ~ "treated cells",
    study_acc=="GSE61628" ~ "smokers vs nonsmokers",
    study_acc=="GSE33338" ~ "all smokers",
    type == "all nicotine dependent" ~ "treated cells",
    TRUE ~ type
  )
  ) %>%
  mutate(type=str_replace_all(type, "-", ""),
         type=str_replace_all(type, "smokig|smoing", "smoking history"),
         type=str_replace_all(type, "smoker\\b", "smokers"),
         type=case_when(
          str_detect(type, "all smokers") ~ "all smokers",
          str_detect(type,"treated cells") ~ "treated cells",
          str_detect(type, "smokers vs nonsmokers") ~ "smoking history",
          type=="not relevant" | str_detect(type, "no smoking information") ~ "no smoking information",
          type=="NA" & (design=="all nonsmokers" | design== "all smokers") ~ design,
          type=="NA" & (design == "current and former smokers" | str_detect(design, "all smokers")) ~ "all smokers",
          type=="NA" & design=="never smokers" ~ "all nonsmokers",
          type=="NA" & design=="nicotine receptor KD" ~ "no smoking information",
          TRUE ~ type)) 
  
#completed_gs2 %>% filter(type=="NA")

completed_gs3  <- completed_gs2 %>%
  mutate(type=case_when(
    study_acc=="SRP096285" ~ "all nonsmokers",
    study_acc=="SRP115956"  ~ "smoking history",
    type=="NA" ~ "not relevant",
    keep=="yes" & type=="all smokers" ~ "smoking history",
    type=="treated cells" & keep=="no" ~ "not relevant",
    type=="no smoking information" ~ "not relevant",
    TRUE ~ type
  )) %>%
  mutate(type=ifelse(type=="smoking history", "smoking", type)) 

# table(completed_gs3$keep)
# table(completed_gs3$type)
# 
# completed_gs3 %>% filter(keep=="yes", type=="treated cells", treatment=="NA") # none
# completed_gs3 %>% filter(keep=="yes", tissue2 %in% c("NA", ""), type!="treated cells") # fill in
completed_gs4 <- completed_gs3 %>%
  mutate(tissue2=case_when(
      study_acc=="GSE29007" ~ "large airway epithelium",
      study_acc=="GSE29133" ~ "alveolar epithelium",
      study_acc=="GSE89809" ~ "airway epithelium; airway T cells", 
      study_acc=="GSE36807" ~ "colon",
      study_acc=="GSE61628" ~ "lung epithelial progenitor cells",
      TRUE ~ tissue2
    )
  )

# clean up tissue / treatment labels 
completed_gs5 <- completed_gs4 %>%
  mutate(tissue_descript=tissue2) %>%
  mutate(tissue2=case_when(
    str_detect(tissue2, "airway epitheli") ~ "airway epithelium",
    str_detect(tissue2, "placenta|umbilical|cord blood") ~ "placenta or umbilical cord",
    str_detect(tissue2, "nasal") & str_detect(tissue2, "buccal") ~ "oral epithelium or mucosa;nasal epithelium",
    str_detect(tissue2, "oral|saliva|tongue|buccal") ~ "oral epithelium or mucosa",
    str_detect(tissue2, "nasal|olfactory") ~ "nasal epithelium",
    str_detect(tissue2, "hepatocytes") ~ "liver",
    str_detect(tissue2, "bronchi|HBEC") ~ "bronchial epithelium or brushing",
    str_detect(tissue2, "alveolar") ~ "alveolar macrophages or epithelium",
    str_detect(tissue2, "hippocampus") ~ "brain",
    tissue2=="sputum macrophages" ~ "sputum",
    str_detect(tissue2, "PBMC|lymphocyte|leukocyte|whole blood|platelets|peripheral") | tissue2=="macrophages" ~ "blood", 
    str_detect(tissue2, "lung") & !str_detect(tissue2, "blood") ~ "lung",
    tissue2=="urothelial" ~ "bladder",
    TRUE ~ tissue2  
  ),
  tissue2=str_replace(tissue2, "; ", ";"),
  treatment=case_when(
    treatment=="nicotine exposure" ~ "nicotine",
    treatment %in% c("cigarette smoke extract", "tobacco smoke extract", "cigarette smoke extract exposure",
                     "cigarette smoke extract; other components", "smoke extract") ~ "cigarette smoke extract",
    treatment %in% c("cigarette smoke", "tobacco smoke", "tobacco smoke exposure") ~ "whole cigarette smoke",
    TRUE ~ treatment)) 

# --- fix problem studies --- #
# both treated cells and another category
  
completed_gs7 <- completed_gs5 %>% 
  mutate(type=case_when(
    study_acc=="GSE76327" ~ "smoking history", # the treated cells are NOT present
    TRUE ~type))  %>%
  select(-smok_grps)

# separate out GSE12587
to_add <- my_gs %>%
  filter(study_acc %in% (completed_gs7 %>% 
    filter(study_acc=="GSE12587") %>%
    separate_rows(studies, sep=";") %>%
    pull(studies) )) %>%
  select(-smok_grps, -`...12`) %>%
  mutate(tissue_descript=tissue2)
  
completed_gs8 <- completed_gs7 %>%
  filter(study_acc!="GSE12587") %>%
  bind_rows(to_add) %>%
  select(-studies, -design) %>%
  mutate(across(everything(), ~ifelse(.=="NA" | .=="", NA, .)))  


# ---- filter by what is present.... ---- #
exp_sample_map <- read_csv(sprintf("%s/01_sample_lists/rb_metadata/human_microarray_exp_to_sample.csv", RB.PATH)) %>%
  bind_rows(read_csv(sprintf("%s/01_sample_lists/rb_metadata/human_rnaseq_exp_to_sample.csv", RB.PATH)))
exp_sample_map2 <- exp_sample_map %>% semi_join(completed_gs8, by="study_acc") %>% distinct()
length(unique(exp_sample_map2$sample_acc)) # 29467
exp_sample_map2_c <- exp_sample_map2 %>% group_by(study_acc) %>% count()
annot_studies2 <- completed_gs8 %>% left_join(exp_sample_map2_c) %>% rename(present_samples=n)
sum(annot_studies2$present_samples) # 32192
sample_metadata_filt <- read_csv(sprintf("%s/sample_metadata_filt.csv", RB.PATH),
                                 col_types="cccccdldcc")
sex_lab <- sample_metadata_filt %>% 
  select(sample_acc, sex_lab, present, num_reads, label_type, p_male) %>%
  pivot_wider(names_from=label_type, values_from=sex_lab)

sex_lab2 <- sex_lab %>% 
  inner_join(exp_sample_map2) %>% 
  inner_join(completed_gs8 %>% select(study_acc, keep, type)) %>%
  mutate(across(c(metadata, expression),
                ~ifelse(is.na(.), "unlabeled", .))) 
length(unique(sex_lab2$sample_acc)) # --> 19383 out of 29467
length(unique(sex_lab2$study_acc)) # --> 267 out of 327
sex_lab2 %>% write_csv("data/smok_samples_w_sl.csv")

study_counts <- sex_lab2 %>% group_by(study_acc) %>% count()
completed_gs8_f <- completed_gs8 %>%
  right_join(study_counts, by="study_acc") %>%
  select(-num_samples) %>%
  rename(num_samples=n) 


# --- manually annotate treated cell info --- #
completed_gs8_f %>% 
  filter(type=="treated cells" & 
           keep=="yes") %>%
  write_csv("data/treated_cls_to_annot.csv")

# STOP - wait to annotate - #
annot_trt <- read_csv("data/treated_cls_to_annot_v2.csv") %>%
  select(study_acc, tissue2, tissue_descript)
trt2 <- completed_gs8_f %>% 
  select(-tissue2, -tissue_descript) %>%
  inner_join(annot_trt, by="study_acc") 

annot_df_clean <- completed_gs8_f %>%
  anti_join(annot_trt, by="study_acc") %>%
  bind_rows(trt2)

# --- write it out --- #
annot_df_clean %>%
  mutate(type=ifelse(type=="smoking", "smoking history", type)) %>%
  mutate(tissue2=ifelse(tissue2=="blood - lymphocytes", "blood", tissue2)) %>%
  rename(included=keep,
           study_type=type,
           tissue=tissue2) %>%
  write_csv("data/supp_tables/supp_table_1_annot.csv") # supplementary table 1


