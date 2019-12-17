#First Pass of IN/OUT System Wide (but can filter by Busnes Unit later)
#Setup and Import of Files, two excel b/c FMIS download limitation
library(tidyverse)
library(lubridate)
#devtools :: install_github ("zhiruiwang/RTableau")
library (RTableau)
library(kableExtra)
library(scales)
library(knitr)


#Setup and Load Data ------------------------------------------
# Return of code Block is a clean tibble called Full_YTD
#--------------------------------------------------------------
use_python("/usr/local/bin/python3")
#Functions Declaration
#Export data to TDE 
Write_to_TDE <- function(dataset, path){
  RTableau:::write_tableau(as.data.frame(dataset), path, spatial_columns = NA, spatial_indicator = TRUE, add_index = FALSE)
}

#A function that does this sigle read_xlsx assignment
#Oct2018 <- readxl::read_xlsx("SLT_SCRD_INOUT_CHARGES_V3_Oct-2018.xlsx", skip = 1)
#NOTE for global scope "envir = .GlobalEnv" option in assign, the assignment scope without it is local to fnt
ipath_list_xlsx <- function(single_month, query_name){
  #print(x)
  #print(query_name)
  imonth <- month.abb[as.Date(paste('01', single_month), format='%d %b %Y') %>% lubridate::month()]
  iyear <- as.Date(paste('01', single_month), format='%d %b %Y') %>% lubridate::year()
  ipath <- stringr::str_c(query_name,"_",imonth,"-",iyear,".xlsx")
  #print(imonth)
  #print(iyear)
  assign(single_month, readxl::read_xlsx(ipath, skip = 1), envir = .GlobalEnv)
  #print(ipath)
}

#Configuration Section
# List of Bind Items
lineup <- list(Oct2018, Nov2018, Dec2018, Jan2019, Feb2019, Mar2019, Apr2019, May2019, Jun2019, Jul2019, Aug2019, Sep2019)
#lineup2 <- list(Oct2018, Nov2018, Dec2018, Jan2019, Feb2019, Mar2019)
#lineups_str <- list("Oct2018", "Nov2018", "Dec2018", "Jan2019", "Feb2019", "Mar2019", "Apr2019", "May2019", "Jun2019", "Jul2019", "Aug2019", "Sep2019")
lineup_vec <- c("Oct2018", "Nov2018", "Dec2018", "Jan2019", "Feb2019", "Mar2019", "Apr2019", "May2019", "Jun2019", "Jul2019", "Aug2019", "Sep2019")
Keep <- c("Incoming", "Outgoing")

# In's are Receipt for Inspection and Putaways
Incoming <- c('010','020')
#Out's or Return to Vendor 012, Scraps 051,054, Usage 030 currently lumped but can be spliced out
# 030 Splice is Evertt/E&M definition is No Destination Unit
Outgoing <- c('012','030','051','054')
#Internal is Intra-System Transaction
Internal <- c('010','022','024','031','041','042','050','060')
Internal_Remove <- c('022','031','042','060')
BU_remove_list <- c('CS003')
#CS003 is coded as CS but is a Capital Spare Designation and filtered out downstream 
CentralStore <- c('CS001','CS002','CS004')
#Logic Levle Needs an Adjustment_Type correction for 050 b/c both 
#Decrease and Increase treated as Positive in DB respresentation
#In contracts 041 has same Adjustment_Type correct but handle properly already at DB level
#
#Handle Adjustment Here 


setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
#Import Excel with ReadXl conflict on read function 
#FMIS QUERY Name: SLT_SCRD_INOUT_CHARGE_V3 many chunks b/c FMIS times-out at about 100K Observations
#Adjustment Type added at Query b/c 050 did NOT differentiate decrease or increase user adjustments
#Will Send lineup to the injestion of excel_function. 
#Oct2018 <- readxl::read_xlsx("SLT_SCRD_INOUT_CHARGES_V3_Oct-2018.xlsx", skip = 1) #See ipath_list_xlsx fnt
#Tricked read_xlsx to see vector "Loc 4" as character by putting Dummy String "SLT" in 1st observation
#Jul2019 <- readxl::read_xlsx("SLT_SCRD_INOUT_CHARGES_V3_Jul-2019.xlsx", skip = 1)

#Maping above read_xlsx embedding inside ipath_list_xlsx fnt, iterating thru lineup_vec with map 
map(lineup_vec, ipath_list_xlsx, query_name="SLT_SCRD_INOUT_CHARGES_V3")

#Binding Chunks
##Full_YTD_new <- bind_rows(lineup)
#Half_YTD <- bind_rows(lineup2)


#Filter out CS003 --Captial Spares and Confuse analysis
#AND Filter out Blacklist Transactioned Types 
Full_YTD_filtered <- Full_YTD_new %>% filter(!Unit %in% BU_remove_list, !`Transaction Type` %in% Internal_Remove)
#Mutation and cleaning whitespace in vector name or whatever rename you feel like her
Full_YTD_filtered <- Full_YTD_filtered %>%  
                      mutate(Central_or_Base = 
                              case_when(`Transaction Type` == '030' & Unit %in% CentralStore ~ "Central",
                                        `Transaction Type` == '030' & !Unit %in% CentralStore ~ "Base")
                             )

Full_YTD_filtered_mutated <- Full_YTD_filtered %>% 
                                  mutate(Trans_Aggregate = 
                                        case_when(`Transaction Type` %in% Incoming ~ "Incoming",
                                                  `Transaction Type` %in% Outgoing ~ "Outgoing",
                                                  `Transaction Type` %in% Internal ~ "Internal",
                                                  TRUE ~ "NoAggTransType"
                                                )
                                      )
######
#End of Data Prep and Handling any code above this line can be relatively safely ignore
#Return of this whole section is cleaned DataFrame call
# Clean DF name: "Full_YTD_filtered_mutated"


#Exploratory Analysis Section -------------------------------------------
#Find details and anamolyes of your data and 
#Don't skip this Step (Everyone wants to skip this step), 
#its critical to getting to understand your data
#You can also do it in Terminal session of R


#Post Setup and Data Exploration and Cleaning -- Now heart of Analysis ---------------------------------------
#Transaction Code Incoming 020, Outgoing 030, CycleCount 041, User Adj. 050
SnapShot_full_filtered_grouped <- Full_YTD_filtered_mutated %>% 
                                  group_by(Trans_Aggregate,`Transaction Type`,Type,Central_or_Base) %>% 
                                  summarise(Cnt = n(), SumTC = sum(`Total Cost`))
#Manual Adjustment to Data because Business Logic necessitates it
#1st the two 010 and 020 Incoming Code with a decrease Adj_Type is incorrect need to make it Zero 
#2nd 024 Decrease needs to be Negative Sign

###INCORRECT###
#There is inconsistant handling of Incoming shouldn't Decrease to offset, just do a 060 bin-to-bin like Normal
#Convoluted logic with the filter, very hard to read b/c Not negates both sides of AND indivdually and not the whole
#Just Remove both Incoming & Decrease Lines
#SnapShot_full_filtered_grouped <- SnapShot_full_filtered_grouped %>% 
#                                  filter(!(`Transaction Type` %in% Incoming & !is.na(Type)))
###END-INCORRECT###

#2nd Executed --- Flip Sign of 050 Decrease
SnapShot_full_filtered_grouped <- SnapShot_full_filtered_grouped %>% mutate(SumTC=
                                          replace(SumTC, `Transaction Type` == '050' & Type == 'D', -1 * SumTC))

#Highlevel
Summary_INOUT <- SnapShot_full_filtered_grouped %>% group_by(Trans_Aggregate) %>% 
                                                    summarise(SumCnt = sum(Cnt), SumTC = sum(SumTC))


#Plot or KableTable Output ---------------------------------------------------
KableTbl <- Summary_INOUT %>% filter(Trans_Aggregate %in% Keep) %>% 
                            select(Trans_Aggregate, SumTC) %>% 
                            pivot_wider(names_from = Trans_Aggregate, values_from = SumTC)
                        
# Hardcodying Data from KJ's email about Oct18 & Oct19 
KableTbl <- KableTbl %>% mutate(Delta = Incoming - Outgoing,
                                Oct18 = 69692697, Oct19 = 67791629,
                                DeltaFY = Oct19 - Oct18,
                                Unaccounted = Delta - DeltaFY,
                                Pct = scales::percent(Unaccounted/Oct19))
#Formatting for Dollar()
KableTblDollar <- KableTbl %>% mutate_if(is.double,dollar, negative_parens = TRUE)
#KableExtra
KableTblDollar %>%  kable(caption = "Inventory System-Wide OverView") %>%
                kable_styling("striped", full_width = F) %>% 
                add_header_above(c("By Transaction Codes" = 3, 
                                    "On-Hand Inventory" = 3,
                                    "Misc" = 2)) 
                

#Write to Output say Tableau tde file -------------------------------------------
#Write_to_TDE(as.data.frame(SnapShot_full),"Snapshot_Full_exCS003.tde")
#Write to Excel
openxlsx::write.xlsx(SnapShot_full_filtered_grouped, file = "~/Desktop/Inventory_INOUT/Scapshot_Full_filter_grouped_new.xlsx")
openxlsx::write.xlsx(Summary_INOUT, file = "~/Desktop/Inventory_INOUT/Summary_INOUT.xlsx")
openxlsx::write.xlsx(temp, file = "~/Desktop/Inventory_INOUT/030_BAse.xlsx")
openxlsx::write.xlsx(temp2, file = "~/Desktop/Inventory_INOUT/030_BAse2.xlsx")
