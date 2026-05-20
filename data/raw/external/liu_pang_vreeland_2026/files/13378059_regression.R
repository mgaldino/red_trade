##################################################################
# This file Runs the regression (Table B2)
##################################################################

library(lmtest)
library(sandwich)

rm(list=ls())
## load packages
library(easypackages)
library(PanelMatch)
library(dplyr)
packages("bpCausal", "panelView", "coda", "countrycode", "RColorBrewer")
set.seed(1234)
load("BSAupdate.RData")
data<-datasave
rm(datasave)

source('plot_function2.R', chdir = TRUE)
source('summary_function.R', chdir = TRUE)

Y <- "distance_idealpoint_cn_lognew"
D <- 'swap_dummy_lag1'
X <-  c('v2x_polyarchy_lag1', 'gdppc_log_new_lag1', 'pop_log_new_lag1',
        'minidist_log_lag1','distance_idealpoint_us_lag_lognew',
        'dep_export_new_lag1','dep_import_new_lag1', 
        'bits_chn_lag1','pta_china_lag1','sco_full_lag1',
        'partner_level_lag1') 
Xnam <- c('V-Dem', 'gdppc(log)', 'popuplation(log)','distance(log)','idealpoint distance with us(log)',
          'export dependence','import dependence', 
          'bit','pta','sco',
          'partner level'
          )
index <- c("ccode", "year")

datarun <- as.matrix(data[, c(index, Y, D, X)])
datarun <- datarun[order(datarun[, index[1]], datarun[, index[2]]),]

datarun <- data.frame(datarun)
tapply(datarun$swap_dummy_lag1, datarun$ccode,sum) 
data2 <- subset(datarun,swap_dummy_lag1==1)

data2$year <- as.integer(data2$year)


# staggered adoption
datarun[datarun$ccode==140&datarun$year>=2018, 4] <- NA 
datarun[datarun$ccode==160&datarun$year==2014, 4] <- 1  
datarun[datarun$ccode==339&datarun$year==2018, 4] <- 1 
datarun[datarun$ccode==345&datarun$year==2021, 4] <- NA 
datarun[datarun$ccode==370&datarun$year==2014, 4] <- 1  
datarun[datarun$ccode==370&datarun$year==2015, 4] <- 1
datarun[datarun$ccode==371&datarun$year==2020, 4] <- NA 
datarun[datarun$ccode==371&datarun$year==2021, 4] <- NA 
datarun[datarun$ccode==600&datarun$year==2021, 4] <- NA 
datarun[datarun$ccode==696&datarun$year>=2020, 4] <- NA 
datarun[datarun$ccode==702&datarun$year>=2020, 4] <- NA 
datarun[datarun$ccode==704&datarun$year>=2016, 4] <- NA 
datarun[datarun$ccode==780&datarun$year>=2019, 4] <- NA 
datarun[datarun$ccode==850&datarun$year==2018, 4] <- 1  



datarun2 <- datarun
datarun2$year <- datarun$year-1 

datarun <- na.omit(datarun)
datarun <- data.frame(datarun)

## outcome variable
Yname <- Y
## treatment variable
Dname <- D
## fixed effect beta
Xname <-X
## unit-level random effects variable
Zname <- X
## time-varying random effects variable
Aname <- X

## factor number
r <- 50  

## total number of iterations to run including burnin
niter <- 45000

re <- "both"

## lasso on beta
xlasso <- 1
## lasso on multi level
zlasso <- 0
## lasso on time varying
alasso <- 1
## lasso on factor 
flasso <- 1

############################
## 1. TWFE
############################
TWFE_fit <- function(dvs, ivs, modname, data){
  library(plm)
  Fits <- list()
  for (i in seq_along(modname)){
    f <- as.formula(paste(dvs[i], paste(ivs, collapse=" + "), sep=" ~ "))
    fit <- plm(f, data = data, index = c("ccode", "year"), model = "within")
    Fits[[modname[i]]] <- fit
  }
  return(Fits)
}
m4_twfe <- TWFE_fit(
  dvs = c('distance_idealpoint_cn_lognew'),
  ivs = c('swap_dummy_lag1', 'v2x_polyarchy_lag1', 'gdppc_log_new_lag1', 'pop_log_new_lag1',
          'minidist_log_lag1', 'distance_idealpoint_us_lag_lognew',
          'dep_export_new_lag1','dep_import_new_lag1', 
          'bits_chn_lag1','pta_china_lag1','sco_full_lag1',
          'partner_level_lag1'),
  modname = c('china'),
  data = datarun
)

summary(m4_twfe$china)
vote_full <- m4_twfe$china

coeftest(m4_twfe$china, vcov = vcovHC(m4_twfe$china, type = "HC1", cluster = "group"))

########################
## TWFE Without controls
########################
m4_twfe_nocontrol <- TWFE_fit(
  dvs = c('distance_idealpoint_cn_lognew'),
  ivs = c('swap_dummy_lag1','v2x_polyarchy_lag1', 'gdppc_log_new_lag1', 'pop_log_new_lag1',
          'minidist_log_lag1',
          'distance_idealpoint_us_lag_lognew'),
  modname = c('china'),
  data = datarun
)
summary(m4_twfe_nocontrol$china)
vote_nocontrol <- m4_twfe_nocontrol$china
coeftest(m4_twfe_nocontrol$china, vcov = vcovHC(m4_twfe_nocontrol$china, type = "HC1", cluster = "group"))

#------------------------------
# Co-sponsorship
#------------------------------

library(easypackages)
library(PanelMatch)
library(dplyr)
packages("bpCausal", "panelView", "coda", "countrycode", "RColorBrewer","tidyr")
set.seed(1234)

load("cosponsorship_data.RData") # Load data 
data<-datasave
rm(datasave)
source('plot_function2.R', chdir = TRUE)
source('summary_function.R', chdir = TRUE)

Y <- "co_sp_CHN_all"
D <- 'swap_dummy_lag1'
X <-  c('v2x_polyarchy_lag1', 'gdppc_log_new_lag1', 'pop_log_new_lag1',
        'minidist_log_lag1','distance_idealpoint_us_lag_lognew',
        'dep_export_new_lag1','dep_import_new_lag1', 
        'bits_chn_lag1','pta_china_lag1','sco_full_lag1',
        'partner_level_lag1'
        )
Xnam <- c('V-Dem', 'gdppc(log)', 'popuplation(log)',
          'distance(log)','idealpoint distance with us(log)',
          'export dependence','import dependence', 
          'bit','pta','sco',
          'partner level') 

index <- c("ccode", "year")

datarun <- as.matrix(data[, c(index, Y, D, X)])
datarun <- datarun[order(datarun[, index[1]], datarun[, index[2]]),]


datarun <- data.frame(datarun)
tapply(datarun$swap_dummy_lag1, datarun$ccode,sum) 
data2 <- subset(datarun,swap_dummy_lag1==1)

data2$year <- as.integer(data2$year)


datarun[datarun$ccode==140&datarun$year>=2018, 4] <- NA
datarun[datarun$ccode==160&datarun$year==2014, 4] <- 1  
datarun[datarun$ccode==339&datarun$year==2018, 4] <- 1 
datarun[datarun$ccode==345&datarun$year==2021, 4] <- NA
datarun[datarun$ccode==370&datarun$year==2014, 4] <- 1  
datarun[datarun$ccode==370&datarun$year==2015, 4] <- 1
datarun[datarun$ccode==371&datarun$year==2020, 4] <- NA
datarun[datarun$ccode==371&datarun$year==2021, 4] <- NA 
datarun[datarun$ccode==600&datarun$year==2021, 4] <- NA 
datarun[datarun$ccode==696&datarun$year>=2020, 4] <- NA
datarun[datarun$ccode==702&datarun$year>=2020, 4] <- NA 
datarun[datarun$ccode==704&datarun$year>=2016, 4] <- NA 
datarun[datarun$ccode==780&datarun$year>=2019, 4] <- NA 
datarun[datarun$ccode==850&datarun$year==2018, 4] <- 1  

datarun2 <- datarun
datarun2$year <- datarun$year-1 


datarun <- na.omit(datarun)
datarun <- data.frame(datarun)

## outcome variable
Yname <- Y
## treatment variable
Dname <- D
## fixed effect beta
Xname <-X
## unit-level random effects variable
Zname <- X
## time-varying random effects variable
Aname <- X

## factor number
r <- 15 

## total number of iterations to run including burnin
niter <- 45000
## two-way re: unit, time, none, both
re <- "both"

## lasso on beta
xlasso <- 1
## lasso on multi level
zlasso <- 0
## lasso on time varying
alasso <- 1
## lasso on factor 
flasso <- 1

############################
## 1. TWFE
############################
TWFE_fit <- function(dvs, ivs, modname, data){
  library(plm)
  Fits <- list()
  for (i in seq_along(modname)){
    f <- as.formula(paste(dvs[i], paste(ivs, collapse=" + "), sep=" ~ "))
    fit <- plm(f, data = data, index = c("ccode", "year"), model = "within")
    Fits[[modname[i]]] <- fit
  }
  return(Fits)
}
m4_twfe <- TWFE_fit(
  dvs = c('co_sp_CHN_all'),
  ivs = c('swap_dummy_lag1', 'v2x_polyarchy_lag1', 'gdppc_log_new_lag1', 'pop_log_new_lag1',
          'minidist_log_lag1','distance_idealpoint_us_lag_lognew',
          'dep_export_new_lag1','dep_import_new_lag1', 
          'bits_chn_lag1','pta_china_lag1','sco_full_lag1',
          'partner_level_lag1'),
  modname = c('china'),
  data = datarun
)

summary(m4_twfe$china)
cosponsor_full <- m4_twfe$china

coeftest(m4_twfe$china, vcov = vcovHC(m4_twfe$china, type = "HC1", cluster = "group"))

########################
## TWFE Without controls
########################
m4_twfe_nocontrol <- TWFE_fit(
  dvs = c('co_sp_CHN_all'),
  ivs = c('swap_dummy_lag1','v2x_polyarchy_lag1', 'gdppc_log_new_lag1', 'pop_log_new_lag1',
          'minidist_log_lag1',
          'distance_idealpoint_us_lag_lognew'),
  modname = c('china'),
  data = datarun
)
summary(m4_twfe_nocontrol$china)
cosponsor_nocontrol <- m4_twfe_nocontrol$china

coeftest(m4_twfe_nocontrol$china, vcov = vcovHC(m4_twfe_nocontrol$china, type = "HC1", cluster = "group"))



#################
## Report a table
#################
library(stargazer)
library(lmtest)
library(sandwich)

se_vote_full <- sqrt(diag(vcovHC(vote_full, type = "HC1", cluster = "group")))
se_vote_nocontrol <- sqrt(diag(vcovHC(vote_nocontrol, type = "HC1", cluster = "group")))
se_cosponsor_full <- sqrt(diag(vcovHC(cosponsor_full, type = "HC1", cluster = "group")))
se_cosponsor_nocontrol <- sqrt(diag(vcovHC(cosponsor_nocontrol, type = "HC1", cluster = "group")))

stargazer(vote_nocontrol,vote_full, cosponsor_nocontrol,cosponsor_full,
          type = "latex",
          se = list(se_vote_full, se_vote_nocontrol,
                    se_cosponsor_full, se_cosponsor_nocontrol),
          dep.var.labels = c("UNGA Voting Alignment","Co-sponsorship"),
          covariate.labels = c("BSA (lag 1)",
                               "V-Dem", "GDPpc (log)", "Population (log)",
                               "Distance (log)", "Distance to US (log)",
                               "Export dependence", "Import dependence",
                               "BIT", "PTA", "SCO", "Partner level"),
          add.lines = list(c("Country FE", "Yes", "Yes", "Yes", "Yes"),
                           c("Year FE", "Yes", "Yes", "Yes", "Yes")),
          omit.stat = c("f", "adj.rsq"),
          digits = 3,
          notes = "Cluster-robust SEs at the country level in parentheses.",
          title = "Effect of Bilateral Swap Agreements on UN Alignment")
