# Lorber-Egeghy-East-Model: Concentration Summary Statistics
# to Exposure Distributions
#
# Learn more by entering "?LorberEgeghyModel::LEEM"
# into the console or running the line in R.

LEEM <- function(data,factors,absorption = NULL,wtcol,n,seed = NULL){

  # 1. Convert all inputs to lowercase
  colnames(data)<- tolower(colnames(data))
  colnames(factors) <-tolower(colnames(factors))
  wtcol<-tolower(wtcol)
  # function which converts entire dataframe to lowercase
  units <- data$units


  lowerdf <- function(x){

    m <- colnames(x)
    y <- data.frame(lapply(x,
                           function(variables){
                             if (is.character(variables)) {
                               return(tolower(variables))
                             } else {
                               return(variables)
                             }
                           }),
                    stringsAsFactors = FALSE)
    colnames(y) <- m
    return(y)
  }

  data <- lowerdf(data)
  factors <- lowerdf(factors)
  data$units <- units


  # 2. TESTING
  # 2A. Check "data" for required column names.
  requiredcols <- c("sample size","media","chemical","units",
                    "min","max","median","mean","sd","gm","gsd",
                    "p10","p25","p75","p90","p95","p99")
  if (sum(requiredcols %in% colnames(data)) != length(requiredcols)){
    mssng <- paste(str_c(setdiff(requiredcols,colnames(data))), collapse = ", ")
    stop(str_c("Missing data input column name(s): ",mssng ,
               ". Please rename or add column to data input dataframe."))
  }

  # 2B. Check "factors" for column names.
  requiredcols <- c("path","media","individual","factor")
  if (sum(requiredcols %in% colnames(factors)) != length(requiredcols)){
    mssng <- paste(str_c(setdiff(requiredcols,colnames(factors))), collapse = ", ")
    stop(str_c("Missing factors input column name(s): ",mssng ,
               ". Please rename or add column to factors input dataframe."))
  }

  # 2C. Check "absorption" for column names.
  if(is.null(absorption)){
    absorption <- setNames(data.frame(matrix(ncol = 4, nrow = 1)),
                           c("chemical","path","media","absorption"))
  }
  absorption <- lowerdf(absorption)
  colnames(absorption) <- tolower(colnames(absorption))
  requiredcols <- c("chemical","path","media","absorption")
  if (sum(requiredcols %in% colnames(absorption)) != length(requiredcols)){
    mssng <- paste(str_c(setdiff(requiredcols,colnames(absorption))), collapse = ", ")
    stop(str_c("Missing absorption input column name(s): ",mssng ,
               ". Please rename or add column to absorption input dataframe."))
  }

  # 2D. Detect Weighting Column in Data.
  if (!tolower(wtcol) %in% tolower(colnames(data))){
    stop((str_c("Column '", wtcol, "' not detected in data column names.")))
  }

  # 2E. Make sure Weighting Column is a numeric.
  if(!is.numeric(data[,(wtcol)])){
    stop((str_c("Column '", wtcol, "' is not a numeric. Please convert or specify a different column.")))
  }

  # 2F. Detect Factors for all media
  if (length(setdiff(unique(data$media), unique(factors$media))) > 0){
    stop((str_c("Media '", setdiff(unique(data$media), unique(factors$media)),
                "' not detected in factors media column.")))
  }

  # 2G. Detect Absorption Fractions for all unique chemical/media/pathway groups.
  possible <- expand.grid(unique(data$chemical),unique(data$media),unique(factors$path))
  inabs    <- absorption[c("chemical","media","path")]
  colnames(possible) <- c("chemical","media","path")

  if (nrow(setdiff(possible,inabs)) >= 1){
    warning("Some absorption fractions not provided and a value of 1 will be used.
           See output for missing fractions.")

    absorption <- bind_rows(absorption,setdiff(possible,inabs))
    absorption <- absorption[complete.cases(absorption[c("chemical","media","path")]),]
    absorption$missing <- NA
    absorption$missing[is.na(absorption$absorption)] <- "yes"
    absorption$missing[is.na(absorption$missing)] <- "no"
    absorption$absorption[is.na(absorption$absorption)] <- 1

  }

  # 3. Set seed if none specified.
  if(is.null(seed)) seed <- 12345
  set.seed(seed)

  #-> 15. ID unique individuals for step 15.
  id <- factors[c("individual","media","path")]

  # 4A. Units to ng/m3,ng/L,or ng/g
  data<- data %>% dplyr::mutate(UNITFACTOR = case_when(
    (units %in% c("ng/m³","ng/L","ng/g","µg/kg","ug/kg","pg/mL","pg/ml","ng/m3")) ~ 1,
    (units %in% c("pg/m³","pg/g","pg/m3")) ~ 0.001,
    (units %in% c("ng/ml","ng/mL","ug/l","µg/L","ug/m³","µg/m³","ug/m3","µg/m3")) ~ 1000)) %>%
    mutate_at(c("min","max","median","mean","sd","gm","gsd","p10","p25","p75","p90","p95","p99"),~.*UNITFACTOR) %>%
    mutate(units = case_when(
      (units %in% c("ug/m3","µg/m³","pg/m³","ng/m³","ng/m3","pg/m3")) ~ "ng/m3",
      (units %in% c("ng/ml","ng/mL","ug/l","ug/L","µg/l","µg/L","pg/ml","pg/mL","ng/L")) ~ "ng/L",
      (units %in% c("pg/g","µg/kg","ug/kg","ng/g")) ~ "ng/g")) %>%
    select(-UNITFACTOR)

  # 4B. Unit test for states among media.
  ut <- split(data,data$media)

  testunits <-function(x){
    if (length(unique(x$units)) > 1){
      cat(str_c("
  Different unit states for media in data input. ",unique(x$media)," units are: ",
                paste(unique(x$units),collapse = ", "),".
  Please resolve to one state (gas, solid or liquid) in input.

            "))
      flag <- 1
    }
  }

  ut <- length(bind_rows(lapply(ut,testunits)))
  if (ut>1){
    stop("Resolve different states in input data described above to continue.
       ")
  }

  # 5. GM/GSD Estimation sequence

  # 5A. SE to SD if it exists.
  if ("se" %in% colnames(data)){
    data <- data %>% mutate(sd = if_else(!is.na(sd),sd,sd*sqrt(`sample size`)))
  }

  # 5B. Estimate gm using Pleil 1.
  data <- data %>% mutate(gm = if_else(!is.na(gm),gm , median))

  # 5C. Estimate gm using Pleil 2.
  data <- data %>% mutate(gm = if_else(!is.na(gm),gm , mean/(1+0.5 *(sd/mean)^2)))

  # 5D. Estimate gsd using Pleil 1.
  data <- data %>% mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(p10/gm)/qnorm(.10)))) %>%
    mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(p25/gm)/qnorm(.25)))) %>%
    mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(p75/gm)/qnorm(.75)))) %>%
    mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(p90/gm)/qnorm(.90)))) %>%
    mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(p95/gm)/qnorm(.95)))) %>%
    mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(p99/gm)/qnorm(.99))))

  # 5E. Estimate gsd using Pleil 2.
  data <- suppressWarnings(data %>% mutate(gsd = if_else(!is.na(gsd),gsd ,exp(sqrt(2 * log(mean/gm))))))
  # 5F. Estimate gm using Pleil 3.
  data <- data %>% mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(max/gm)/qnorm(1-1/`sample size`))))
  data <- data %>% mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(min/gm)/qnorm(1/`sample size`))))

  # 5G. Estimate mean and sd using "Estimating.datalsdata" Methods (5) and (16). mean calculated from min, median, maximum,
  # and sd from minimum, median, maximum, and range.

  data <- data %>% mutate(mean = if_else(!is.na(mean),mean, (min+2*median+max)/4))
  data <- data %>% mutate(sd = if_else(!is.na(sd),sd, sqrt ((1/12) * ((min-2*median+max)^2)/4 + (max-min)^2)))

  # 5H. Estimate sd using Ramirez & Cox Method and range rule. Applied only if weight  > 10.
  data <- data %>% mutate(sd = if_else((!is.na(sd) & `sample size` > 10),sd, (max-min)/ (3*sqrt(log(`sample size`))-1.5)))
  data <- data %>% mutate(sd = if_else((!is.na(sd) & `sample size` > 10),sd, (max-min)/4))

  # ______________________________ Repeat B - H. ______________________________ #


  # 5I. Estimate gm using Pleil 1.
  data <- data %>% mutate(gm = if_else(!is.na(gm),gm , median))

  # 5J. Estimate gm using Pleil 2.
  data <- data %>% mutate(gm = if_else(!is.na(gm),gm , mean/(1+0.5 *(sd/mean)^2)))

  # 5K. Estimate gsd using Pleil 1.
  data <- data %>% mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(p10/gm)/qnorm(.10)))) %>%
    mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(p25/gm)/qnorm(.25)))) %>%
    mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(p75/gm)/qnorm(.75)))) %>%
    mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(p90/gm)/qnorm(.90)))) %>%
    mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(p95/gm)/qnorm(.95)))) %>%
    mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(p99/gm)/qnorm(.99))))

  # 5L. Estimate gsd using Pleil 2.
  data <- suppressWarnings(data %>% mutate(gsd = if_else(!is.na(gsd),gsd ,exp(sqrt(2 * log(mean/gm))))))

  # 5M. Estimate gm using Pleil 3.
  data <- data %>% mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(max/gm)/qnorm(1-1/`sample size`))))
  data <- data %>% mutate(gsd = if_else(!is.na(gsd),gsd ,exp(log(min/gm)/qnorm(1/`sample size`))))

  # ___________________________________________________________________________ #

  # 5N. Remove Infs.
  data$gm[is.infinite(data$gm)]<- NA
  data$gsd[is.infinite(data$gsd)]<- NA


  # 6. Split by media and chemical.
  md <- split(data,list(data$media,data$chemical),drop = TRUE)

  # 7. Estimate weighted geometric mean and weighted geometric standard deviation.

  wgmwgsd <- function(x){

    # filter out NAs
    x <- x[!is.na(x[wtcol]),]

    # wgm wgsd
    wgm  <- weighted.mean(x$gm[complete.cases(x$gsd,x$gm)],
                          x[,wtcol][complete.cases(x$gsd,x$gm)])
    wgsd <- weighted.mean(x$gsd[complete.cases(x$gsd,x$gm)],
                          x[,wtcol][complete.cases(x$gsd,x$gm)])

    y <- data.frame(wgm,wgsd)

    return(y)
  }


  md<-lapply(md,wgmwgsd)

  # 8. Create concentration curves.
  distributions <- function(x){
    set.seed(seed)
    Concentration<- rlnorm(n,log(x$wgm),abs(log(x$wgsd)))
    Concentration <- data.frame(Concentration)
    return(Concentration)
  }

  conc <- lapply(md,distributions)

  # Add names and remove NAs.

  conc <- bind_rows(conc, .id = "Media Chemical")
  conc <- conc[!is.na(conc$Concentration),]

  # 9. Load Exposure Factors
  factors <-split(factors,list(factors$individual,factors$media,factors$path),drop = TRUE)

  exposurefactors<- function(x){

    myname <- str_c(unique(x$individual)," ",
                    unique(x$media)," ",
                    unique(x$path))

    y <- data.frame(prod(x$factor),unique(x$media))
    colnames(y)<- c(myname,"Media")
    return(y)
  }

  factors<-lapply(factors,exposurefactors)

  # 10. Apply Exposure Factors
  conc2exposure <- function(x){
    # Match Media across factors and concentration
    y<- conc[grepl(as.character(x$Media),conc$`Media Chemical`),]

    # Tidy
    y$`Media Chemical` <- gsub("\\.", " ", y$`Media Chemical` )

    # Create columns for export df
    name <- str_remove(y$`Media Chemical`,as.character(x$Media))
    name <- str_c(colnames(x)[1],name)
    conc <- as.numeric(unlist(y$Concentration))
    exp  <- as.numeric(unlist(x[1]))*conc

    # Bind and export
    y <- data.frame(cbind(name,conc,exp))
    return(y)
  }

  result <- bind_rows(lapply(factors,conc2exposure))

  # 11. Apply Absorption Fractions
  # Create like terms by using 'group column identifier
  result$group <- gsub(paste0(unique(id$individual),collapse = "|"),"", result$name)
  result$group <- substring(result$group,2)

  absorption$group <- str_c(absorption$media," ",absorption$path," ",absorption$chemical)


# merge and multiply
  result <- merge(result,absorption,by ="group")
  result$exp<-as.numeric(result$exp)*as.numeric(result$absorption)
  result$conc <- as.numeric(result$conc)

  result <- result[!colnames(result) %in% colnames(absorption)]
  absorption <- absorption[!colnames(absorption) %in% "group"]

  # 12. Summarize Exposure Data
  thesummary <- split(result,result$name)

  getsummary <- function(x){

    Output <- t(c("Exposure", as.character(unique(x$name)), quantile(as.numeric(as.character(x$exp)),c(0,.10,.5,.75,.95,1))))
    colnames(Output)[1:8]<-c("Output","Scenario","Min","10th%","Median","75th%","95th%","Max")
    Concentration <- t(c("Concentration", as.character(unique(x$name)), quantile(as.numeric(as.character(x$conc)),c(0,.10,.5,.75,.95,1))))

    y <- data.frame(rbind(Output,Concentration))

    return(y)
  }


  thesummary <- lapply(thesummary,getsummary)
  thesummary  <- bind_rows(thesummary)

  colnames(thesummary)[1:8]<-c("Output","Scenario","Min","10th%","Median","75th%","95th%","Max")
  thesummary$Units <- "ng/day"
  thesummary$WeightedBy <- wtcol

  colnames(result) <- c("Scenario","Concentration","Exposure")

  # 13. Subset used and not used data
  used     <-  data[complete.cases(data$gsd,data$gm,data[,(wtcol)]),]
  notused  <-  data[!complete.cases(data$gsd,data$gm,data[,(wtcol)]),]


  # 14. Convert classes and apply 4 significant figures

  # 14A. Raw
  result$Concentration <- signif(as.numeric(as.character(result$Concentration)),4)
  result$Exposure <- signif(as.numeric(as.character(result$Exposure)),4)

  # 14B. Summary
  thesummary[c("Min","10th%","Median","75th%","95th%","Max")]<-
    lapply(thesummary[c("Min","10th%","Median","75th%","95th%","Max")],as.character)

  thesummary[c("Min","10th%","Median","75th%","95th%","Max")]<-
    lapply(thesummary[c("Min","10th%","Median","75th%","95th%","Max")],as.numeric)

  thesummary[c("Min","10th%","Median","75th%","95th%","Max")]<-
    signif(thesummary[c("Min","10th%","Median","75th%","95th%","Max")],4)

  # 15. Count of datasets used

  counted <- split(used, list(used$chemical))

  numberofstudies <- function(x){

    scount<-data.frame(t(c(unique(x$chemical),table(x$media))))
    colnames(scount) <-  c("Chemical",names(table((x$media))))

    return(scount)
  }

  scount <- bind_rows(lapply(counted,numberofstudies))


  # 16. Parse "Scenario" column for raw data and summary

  # 16A. Construct Legend ID
  unique(id)
  unic <- unique(used$chemical)

  chemname <- function(x){
    return(cbind(unique(id),"chemical" = x))
  }

  id <- bind_rows(lapply(unic,chemname))
  id$Scenario <- str_c(id$individual," ",
                       id$media," ",
                       id$path," ",
                       id$chemical)
  colnames(id)<- c("Individual","Media","Path","Chemical","Scenario")

  # 16B. Merge and tidy results and summary
  result     <- merge(id,result)
  thesummary <- merge(id,thesummary)

  thesummary <-thesummary[!names(thesummary) %in% c("Scenario")]
  result     <- result[!names(result) %in% c("Scenario")]


  # 17. Create metadata
  namer <- function(name){

    date   <- Sys.time()
    year   <- substr(date,1,4)
    month  <- substr(date,6,7)
    day    <- substr(date,9,10)
    hour   <- as.numeric(substr(date,12,13))
    minute <- substr(date,15,16)

    if (hour > 12){
      hour <- as.character(hour-12)
      minute <- paste0(minute,"PM")
    } else {
      minute <- paste0(minute,"AM")
    }

    filename <- paste0(name," ",hour,minute," ",month,"",day,"",year)

    return(filename)
  }
  filename  <- namer('LEEM Results')


  metadata <- data.frame("Name" = filename,
                         "n" = n,
                         "Seed" = seed,
                         "Chemicals" = paste(unique(data$chemical),collapse = ", "),
                         "Media" = paste(unique(data$media),collapse = ", "))

  metadata[]<- lapply(metadata, as.character)


  colnames(absorption)<- str_to_title(colnames(absorption))
  colnames(scount) <- str_to_title(colnames(scount))

  # 18. Compile list of results
  finished <- list("Summary"   = thesummary,
                   "Used Input"      = used,
                   "Excluded Input"  = notused,
                   "Used Dataset Counts" = scount,
                   "Absorption Fractions" = absorption,
                   "Raw"       = result,
                   "Metadata"  = metadata)

  cat(str_c("LEEM-R Complete.

"))

  return(finished)
}

