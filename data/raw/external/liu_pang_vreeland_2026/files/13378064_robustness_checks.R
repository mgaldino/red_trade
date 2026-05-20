##################################################################
# This file conducts robustness checks (Figure C1, C2, C3)
##################################################################
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
        'dep_export_new_lag1','dep_import_new_lag1', 
        'bits_chn_lag1','pta_china_lag1','sco_full_lag1',
        'minidist_log_lag1','partner_level_lag1',
        'distance_idealpoint_us_lag_lognew') 
Xnam <- c('V-Dem', 'gdppc(log)', 'popuplation(log)',
          'export dependence','import dependence', 
          'bit','pta','sco',
          'distance(log)','partner level',
          'idealpoint distance with us(log)')
X <-NULL
Xnam<-NULL

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


out1 <- bpCausal(data = datarun, index = index, 
                 Yname = Yname, Dname = Dname, 
                 Xname = Xname, Zname = NULL, Aname = Aname, 
                 re = re, r = r, niter = niter, burn=10000, 
                 xlasso = xlasso, zlasso = zlasso,
                 alasso = alasso, flasso = flasso)


mm <- 15000
a <- 15
tt <- out1$tr.unit.pos

gg <- table(out1$raw.id.tr)

hh <- as.numeric(names(gg))

country <- countrycode(hh, "cown", "country.name")


#--------------------------
# Figure C1(a) ATT
#---------------------------
eout1 <- effSummary(out1, usr.id =NULL , burn =mm,  cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eout1, type = "eff", x1.pos = 0, y.pos = 0,  xlim = c(-30, 15))
p1.att <-p1.att + scale_y_continuous(limits = c(-1.6, 1.1))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att


#----------------------------
# Heterogeneous effects
#----------------------------
load("BSAupdate.RData")
data_full<-datasave
rm(datasave)

source('plot_function2.R', chdir = TRUE)
source('summary_function.R', chdir = TRUE)

Y <- "distance_idealpoint_cn_lognew"
D <- 'swap_dummy_lag1'
X <-  c('v2x_polyarchy_lag1', 'gdppc_log_new_lag1', 'pop_log_new_lag1',
        'dep_export_new_lag1','dep_import_new_lag1', 
        'bits_chn_lag1','pta_china_lag1','sco_full_lag1',
        'minidist_log_lag1','partner_level_lag1',
        'distance_idealpoint_us_lag_lognew') 
Xnam <- c('V-Dem', 'gdppc(log)', 'popuplation(log)',
          'export dependence','import dependence', 
          'bit','pta','sco',
          'distance(log)','partner level',
          'idealpoint distance with us(log)')
index <- c("ccode", "year")

datarun_full <- as.matrix(data_full[, c(index, Y, D, X)])
datarun_full <- datarun_full[order(datarun_full[, index[1]], datarun_full[, index[2]]),]

datarun_full <- data.frame(datarun_full)
tapply(datarun_full$swap_dummy_lag1, datarun_full$ccode,sum) 
data2_full <- subset(datarun_full,swap_dummy_lag1==1)

data2_full$year <- as.integer(data2_full$year)


# staggered adoption
datarun_full[datarun_full$ccode==140&datarun_full$year>=2018, 4] <- NA 
datarun_full[datarun_full$ccode==160&datarun_full$year==2014, 4] <- 1  
datarun_full[datarun_full$ccode==339&datarun_full$year==2018, 4] <- 1 
datarun_full[datarun_full$ccode==345&datarun_full$year==2021, 4] <- NA 
datarun_full[datarun_full$ccode==370&datarun_full$year==2014, 4] <- 1  
datarun_full[datarun_full$ccode==370&datarun_full$year==2015, 4] <- 1
datarun_full[datarun_full$ccode==371&datarun_full$year==2020, 4] <- NA 
datarun_full[datarun_full$ccode==371&datarun_full$year==2021, 4] <- NA 
datarun_full[datarun_full$ccode==600&datarun_full$year==2021, 4] <- NA 
datarun_full[datarun_full$ccode==696&datarun_full$year>=2020, 4] <- NA
datarun_full[datarun_full$ccode==702&datarun_full$year>=2020, 4] <- NA 
datarun_full[datarun_full$ccode==704&datarun_full$year>=2016, 4] <- NA 
datarun_full[datarun_full$ccode==780&datarun_full$year>=2019, 4] <- NA 
datarun_full[datarun_full$ccode==850&datarun_full$year==2018, 4] <- 1  



datarun2_full <- datarun_full
datarun2_full$year <- datarun_full$year-1 


datarun_full <- na.omit(datarun_full)
datarun_full <- data.frame(datarun_full)

#-----------------------------------------
## Figure C1(c): Developing countries 
#-----------------------------------------
category<-read.csv("ITT_confusion.csv")
advanced<-category%>%filter(Developing==0)%>%pull(Country)

advanced<-c("Canada","United Kingdom","Switzerland","Hungary","Albania",
           "Russia","Ukraine","Belarus","Iceland","South Korea","Japan","Australia","New Zealand")
regi<-countrycode(advanced,"country.name","cown")
regi<- hh[-which(hh%in%regi)] 
regi<-regi[regi!=710]
countrycode(regi,"cown","country.name")

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = c(-2,2.5), xlim = c(-90, 28))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

#------------------------------------------------------------
# ## Figure C1(d):higher than comprehensive cooperative partnership
#------------------------------------------------------------
data4<-subset(datarun_full,swap_dummy_lag1==1)
jj <- tapply(data4$partner_level_lag1, data4$ccode,mean)

ll <- as.numeric(names(jj)[which(jj>=4)])
regi <- hh[which(hh%in%ll)]

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-2, 3))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

#----------------------------------------------------
## Figure C1(e): One Belt One Road
#----------------------------------------------------
data4<-subset(datarun_full,swap_dummy_lag1==1)
BRI <- read.csv("BRI_2020.csv")
ccode <- countrycode(BRI$countryname, "country.name", "cown")
BRI2 <- data.frame(BRI, ccode)

BRI2[BRI2$countryname=="Serbia", 6]<- 345
BRI2<-BRI2%>%filter(is.na(ccode)==FALSE)

BRI3 <- subset(BRI2, year<2019)
regi <- hh[which(hh%in%BRI2$ccode)]

regi2<-c()
for (i in 1:length(regi)){
  ct<-regi[i]
  BRI_i<-BRI2%>%filter(ccode==ct)
  BRIy<-BRI_i$year
  t_i<-data4%>%filter(ccode==ct)
  ty<-t_i$year
  
  dy<-ty[which(ty%in%BRIy)]
  
  if (length(dy)>0){
    regi2<-c(regi2,ct)
  }
}

eouti <- effSummary(out1, usr.id =regi2 , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-3, 2))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att


#-------------------------------------------------------------
## Figure C1(b) : without other BSA partners
#-------------------------------------------------------------

data4<-subset(datarun_full,swap_dummy_lag1==1)
bsaN <- read.csv("bsaNchina.csv")

data4<-subset(datarun,swap_dummy_lag1==1)
ll <- union(unique(bsaN$ccode_A), unique(bsaN$ccode_B))
regi <- hh[which(hh%in%ll)]
country[which(hh%in%ll)]

regi2<-c()
for (i in 1:length(regi)){
  ct<-regi[i]
  BSA_i<-bsaN%>%filter(ccode_A==ct|ccode_B==ct)
  miny<-min(BSA_i$startyear)
  maxy<-ifelse(is.na(max(BSA_i$endyear))==TRUE,2020,max(BSA_i$endyear))
  BSAy<-seq(from=miny,to=maxy,by=1)
  t_i<-data4%>%filter(ccode==ct)
  ty<-t_i$year
  dy<-ty[which(ty%in%BSAy)]
  if (length(dy)>0){
    regi2<-c(regi2,ct)
  }
}

regi <- hh[-which(hh%in%regi2)]
country[-which(hh%in%ll)]

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits =c(-4, 2))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att





##########################################
##########################################
## Figure C3: Add IMF as a new control
##########################################
##########################################
set.seed(1234)
# IMF program
load("BSAupdate.RData")
data<-datasave
rm(datasave)

library(tidyverse)
imf_programs<-read.csv("IMF_program_data.csv")
colnames(imf_programs)[1:2] <- c("iso3c", "country")
colnames(imf_programs)[3:52] <- c(1970:2019)
imf_programs<-imf_programs[,1:52]

imf_programs_long <- imf_programs %>%
  pivot_longer(
    cols = -c(iso3c, country),   
    names_to = "year", 
    values_to = "imf_program"
  ) %>%
  mutate(
    year = as.integer(year),
    imf_program = as.integer(imf_program)
  )

data$iso3c<-countrycode(data$ccode,"cown","iso3c")
data$iso3c<-ifelse(data$ccode==315,"CZE",data$iso3c) 
data$iso3c<-ifelse(data$ccode==345,"YUG",data$iso3c) 
data$iso3c<-ifelse(data$ccode==347,"KSV",data$iso3c) 

data<-left_join(data,imf_programs_long,by=c("year"="year","iso3c"="iso3c"))

imf_na<-data%>%
  filter(is.na(imf_program))
data$imf_program[is.na(data$imf_program)] <- 0

Y <- "distance_idealpoint_cn_lognew"
D <- 'swap_dummy_lag1'
X <-  c('v2x_polyarchy_lag1', 'gdppc_log_new_lag1', 'pop_log_new_lag1',
        'dep_export_new_lag1','dep_import_new_lag1', 
        'bits_chn_lag1','pta_china_lag1','sco_full_lag1',
        'minidist_log_lag1','partner_level_lag1',
        'distance_idealpoint_us_lag_lognew','imf_program') 
Xnam <- c('V-Dem', 'gdppc(log)', 'popuplation(log)',
          'export dependence','import dependence', 
          'bit','pta','sco',
          'distance(log)','partner level',
          'idealpoint distance with us(log)','imf program')
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


out1 <- bpCausal(data = datarun, index = index, 
                 Yname = Yname, Dname = Dname, 
                 Xname = Xname, Zname = NULL, Aname = Aname, 
                 re = re, r = r, niter = niter, burn=10000, 
                 xlasso = xlasso, zlasso = zlasso,
                 alasso = alasso, flasso = flasso)
a <- 15
mm<-15000
tt <- out1$tr.unit.pos

gg <- table(out1$raw.id.tr)

hh <- as.numeric(names(gg))

country <- countrycode(hh, "cown", "country.name")


#--------------------------
# Figure C3(a): ATT
#---------------------------
eout1 <- effSummary(out1, usr.id =NULL , burn =mm,  cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eout1, type = "eff", x1.pos = 0, y.pos = 0,  xlim = c(-30, 15))
p1.att <-p1.att + scale_y_continuous(limits = c(-1.6, 1.1))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

#----------------------------
# Heterogenous effects
#----------------------------
load("BSAupdate.RData")
data_full<-datasave
rm(datasave)

source('plot_function2.R', chdir = TRUE)
source('summary_function.R', chdir = TRUE)

Y <- "distance_idealpoint_cn_lognew"
D <- 'swap_dummy_lag1'
X <-  c('v2x_polyarchy_lag1', 'gdppc_log_new_lag1', 'pop_log_new_lag1',
        'dep_export_new_lag1','dep_import_new_lag1', 
        'bits_chn_lag1','pta_china_lag1','sco_full_lag1',
        'minidist_log_lag1','partner_level_lag1',
        'distance_idealpoint_us_lag_lognew') 
Xnam <- c('V-Dem', 'gdppc(log)', 'popuplation(log)',
          'export dependence','import dependence', 
          'bit','pta','sco',
          'distance(log)','partner level',
          'idealpoint distance with us(log)')
index <- c("ccode", "year")

datarun_full <- as.matrix(data_full[, c(index, Y, D, X)])
datarun_full <- datarun_full[order(datarun_full[, index[1]], datarun_full[, index[2]]),]

datarun_full <- data.frame(datarun_full)
tapply(datarun_full$swap_dummy_lag1, datarun_full$ccode,sum) 
data2_full <- subset(datarun_full,swap_dummy_lag1==1)

data2_full$year <- as.integer(data2_full$year)


# staggered adoption
datarun_full[datarun_full$ccode==140&datarun_full$year>=2018, 4] <- NA 
datarun_full[datarun_full$ccode==160&datarun_full$year==2014, 4] <- 1 
datarun_full[datarun_full$ccode==339&datarun_full$year==2018, 4] <- 1 
datarun_full[datarun_full$ccode==345&datarun_full$year==2021, 4] <- NA
datarun_full[datarun_full$ccode==370&datarun_full$year==2014, 4] <- 1  
datarun_full[datarun_full$ccode==370&datarun_full$year==2015, 4] <- 1
datarun_full[datarun_full$ccode==371&datarun_full$year==2020, 4] <- NA 
datarun_full[datarun_full$ccode==371&datarun_full$year==2021, 4] <- NA 
datarun_full[datarun_full$ccode==600&datarun_full$year==2021, 4] <- NA 
datarun_full[datarun_full$ccode==696&datarun_full$year>=2020, 4] <- NA 
datarun_full[datarun_full$ccode==702&datarun_full$year>=2020, 4] <- NA 
datarun_full[datarun_full$ccode==704&datarun_full$year>=2016, 4] <- NA 
datarun_full[datarun_full$ccode==780&datarun_full$year>=2019, 4] <- NA 
datarun_full[datarun_full$ccode==850&datarun_full$year==2018, 4] <- 1  



datarun2_full <- datarun_full
datarun2_full$year <- datarun_full$year-1 


datarun_full <- na.omit(datarun_full)
datarun_full <- data.frame(datarun_full)

#-----------------------------------------
## Figure C3(c): Developing countries
#-----------------------------------------
advanced<-c("Canada","United Kingdom","Switzerland","Hungary","Albania",
            "Russia","Ukraine","Belarus","Iceland","South Korea","Japan","Australia","New Zealand")
regi<-countrycode(advanced,"country.name","cown")
regi<- hh[-which(hh%in%regi)] 
countrycode(regi,"cown","country.name")

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = c(-2,2.5), xlim = c(-90, 28))
p1.att

p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att


#------------------------------------------------------------
# Figure C3(d): higher than comprehensive cooperative partnership
#------------------------------------------------------------
data4<-subset(datarun_full,swap_dummy_lag1==1)
jj <- tapply(data4$partner_level_lag1, data4$ccode,mean)

ll <- as.numeric(names(jj)[which(jj>=4)])
regi <- hh[which(hh%in%ll)]

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-2, 3))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

#----------------------------------------------------
## Figure C3(e): One Belt One Road
#----------------------------------------------------
data4<-subset(datarun_full,swap_dummy_lag1==1)
BRI <- read.csv("BRI_2020.csv")
ccode <- countrycode(BRI$countryname, "country.name", "cown")
BRI2 <- data.frame(BRI, ccode)

BRI2[BRI2$countryname=="Serbia", 6]<- 345
BRI2<-BRI2%>%filter(is.na(ccode)==FALSE)

BRI3 <- subset(BRI2, year<2019)
regi <- hh[which(hh%in%BRI2$ccode)]

regi2<-c()
for (i in 1:length(regi)){
  ct<-regi[i]
  BRI_i<-BRI2%>%filter(ccode==ct)
  BRIy<-BRI_i$year
  t_i<-data4%>%filter(ccode==ct)
  ty<-t_i$year
  
  dy<-ty[which(ty%in%BRIy)]
  
  
  if (length(dy)>0){
    regi2<-c(regi2,ct)
  }
}

eouti <- effSummary(out1, usr.id =regi2 , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-3, 2))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

#-------------------------------------------------------------
## Figure C3(b): without other BSA partners
#-------------------------------------------------------------

data4<-subset(datarun_full,swap_dummy_lag1==1)
bsaN <- read.csv("bsaNchina.csv")

data4<-subset(datarun,swap_dummy_lag1==1)
ll <- union(unique(bsaN$ccode_A), unique(bsaN$ccode_B))
regi <- hh[which(hh%in%ll)]
country[which(hh%in%ll)]

regi2<-c()
for (i in 1:length(regi)){
  ct<-regi[i]
  BSA_i<-bsaN%>%filter(ccode_A==ct|ccode_B==ct)
  miny<-min(BSA_i$startyear)
  maxy<-ifelse(is.na(max(BSA_i$endyear))==TRUE,2020,max(BSA_i$endyear))
  BSAy<-seq(from=miny,to=maxy,by=1)
  t_i<-data4%>%filter(ccode==ct)
  ty<-t_i$year
  dy<-ty[which(ty%in%BSAy)]
  if (length(dy)>0){
    regi2<-c(regi2,ct)
  }
}


regi <- hh[-which(hh%in%regi2)]
country[-which(hh%in%ll)]

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits =c(-3.5, 2))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att



##########################################
##########################################
## Figure C2: Symmetric Windows
##########################################
##########################################
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
data<-data%>%filter(year>=1997) #force symmetric window
source('plot_function2.R', chdir = TRUE)
source('summary_function.R', chdir = TRUE)

Y <- "distance_idealpoint_cn_lognew"
D <- 'swap_dummy_lag1'
X <-  c('v2x_polyarchy_lag1', 'gdppc_log_new_lag1', 'pop_log_new_lag1',
        'dep_export_new_lag1','dep_import_new_lag1', 
        'bits_chn_lag1','pta_china_lag1','sco_full_lag1',
        'minidist_log_lag1','partner_level_lag1',
        'distance_idealpoint_us_lag_lognew') 
Xnam <- c('V-Dem', 'gdppc(log)', 'popuplation(log)',
          'export dependence','import dependence', 
          'bit','pta','sco',
          'distance(log)','partner level',
          'idealpoint distance with us(log)')

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


out1 <- bpCausal(data = datarun, index = index, 
                 Yname = Yname, Dname = Dname, 
                 Xname = Xname, Zname = NULL, Aname = Aname, 
                 re = re, r = r, niter = niter, burn=10000, 
                 xlasso = xlasso, zlasso = zlasso,
                 alasso = alasso, flasso = flasso)


mm <- 15000
a <- 15

tt <- out1$tr.unit.pos

gg <- table(out1$raw.id.tr)

hh <- as.numeric(names(gg))

country <- countrycode(hh, "cown", "country.name")




#--------------------------
# Figure C2(a): ATT
#---------------------------
eout1 <- effSummary(out1, usr.id =NULL , burn =mm,  cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eout1, type = "eff", x1.pos = 0, y.pos = 0,  xlim = c(-30, 15))
p1.att <-p1.att + scale_y_continuous(limits = c(-1.6, 1.1))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att


#----------------------------
# Heterogeneous effects
#----------------------------
load("BSAupdate.RData")
data_full<-datasave
rm(datasave)

source('plot_function2.R', chdir = TRUE)
source('summary_function.R', chdir = TRUE)

Y <- "distance_idealpoint_cn_lognew"
D <- 'swap_dummy_lag1'
X <-  c('v2x_polyarchy_lag1', 'gdppc_log_new_lag1', 'pop_log_new_lag1',
        'dep_export_new_lag1','dep_import_new_lag1', 
        'bits_chn_lag1','pta_china_lag1','sco_full_lag1',
        'minidist_log_lag1','partner_level_lag1',
        'distance_idealpoint_us_lag_lognew') 
Xnam <- c('V-Dem', 'gdppc(log)', 'popuplation(log)',
          'export dependence','import dependence', 
          'bit','pta','sco',
          'distance(log)','partner level',
          'idealpoint distance with us(log)')
index <- c("ccode", "year")

datarun_full <- as.matrix(data_full[, c(index, Y, D, X)])
datarun_full <- datarun_full[order(datarun_full[, index[1]], datarun_full[, index[2]]),]

datarun_full <- data.frame(datarun_full)
tapply(datarun_full$swap_dummy_lag1, datarun_full$ccode,sum) 
data2_full <- subset(datarun_full,swap_dummy_lag1==1)

data2_full$year <- as.integer(data2_full$year)


# staggered adoption
datarun_full[datarun_full$ccode==140&datarun_full$year>=2018, 4] <- NA
datarun_full[datarun_full$ccode==160&datarun_full$year==2014, 4] <- 1 
datarun_full[datarun_full$ccode==339&datarun_full$year==2018, 4] <- 1 
datarun_full[datarun_full$ccode==345&datarun_full$year==2021, 4] <- NA 
datarun_full[datarun_full$ccode==370&datarun_full$year==2014, 4] <- 1 
datarun_full[datarun_full$ccode==370&datarun_full$year==2015, 4] <- 1
datarun_full[datarun_full$ccode==371&datarun_full$year==2020, 4] <- NA 
datarun_full[datarun_full$ccode==371&datarun_full$year==2021, 4] <- NA 
datarun_full[datarun_full$ccode==600&datarun_full$year==2021, 4] <- NA
datarun_full[datarun_full$ccode==696&datarun_full$year>=2020, 4] <- NA
datarun_full[datarun_full$ccode==702&datarun_full$year>=2020, 4] <- NA 
datarun_full[datarun_full$ccode==704&datarun_full$year>=2016, 4] <- NA 
datarun_full[datarun_full$ccode==780&datarun_full$year>=2019, 4] <- NA
datarun_full[datarun_full$ccode==850&datarun_full$year==2018, 4] <- 1 



datarun2_full <- datarun_full
datarun2_full$year <- datarun_full$year-1 


datarun_full <- na.omit(datarun_full)
datarun_full <- data.frame(datarun_full)

#-----------------------------------------
## Figure C2(c): Developing countries
#-----------------------------------------

advanced<-c("Canada","United Kingdom","Switzerland","Hungary","Albania",
            "Russia","Ukraine","Belarus","Iceland","South Korea","Japan","Australia","New Zealand")
regi<-countrycode(advanced,"country.name","cown")
regi<- hh[-which(hh%in%regi)] 
countrycode(regi,"cown","country.name")

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = c(-2,2.5), xlim = c(-90, 28))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att


#------------------------------------------------------------
# Figure C2(d): higher than comprehensive cooperative partnership
#------------------------------------------------------------
data4<-subset(datarun_full,swap_dummy_lag1==1)
jj <- tapply(data4$partner_level_lag1, data4$ccode,mean)

ll <- as.numeric(names(jj)[which(jj>=4)])
regi <- hh[which(hh%in%ll)]

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-2, 3))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

#----------------------------------------------------
## Figure C2(e): One Belt One Road
#----------------------------------------------------
data4<-subset(datarun_full,swap_dummy_lag1==1)
BRI <- read.csv("BRI_2020.csv")
ccode <- countrycode(BRI$countryname, "country.name", "cown")
BRI2 <- data.frame(BRI, ccode)

BRI2[BRI2$countryname=="Serbia", 6]<- 345
BRI2<-BRI2%>%filter(is.na(ccode)==FALSE)

BRI3 <- subset(BRI2, year<2019)
regi <- hh[which(hh%in%BRI2$ccode)]

regi2<-c()
for (i in 1:length(regi)){
  ct<-regi[i]
  BRI_i<-BRI2%>%filter(ccode==ct)
  BRIy<-BRI_i$year
  t_i<-data4%>%filter(ccode==ct)
  ty<-t_i$year
  
  dy<-ty[which(ty%in%BRIy)]
  
  
  if (length(dy)>0){
    regi2<-c(regi2,ct)
  }
}

eouti <- effSummary(out1, usr.id =regi2 , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-3, 2))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

#-------------------------------------------------------------
## Figure C2(b): without other BSA partners
#-------------------------------------------------------------

data4<-subset(datarun_full,swap_dummy_lag1==1)
bsaN <- read.csv("bsaNchina.csv")

data4<-subset(datarun,swap_dummy_lag1==1)
ll <- union(unique(bsaN$ccode_A), unique(bsaN$ccode_B))
regi <- hh[which(hh%in%ll)]
country[which(hh%in%ll)]

regi2<-c()
for (i in 1:length(regi)){
  ct<-regi[i]
  BSA_i<-bsaN%>%filter(ccode_A==ct|ccode_B==ct)
  miny<-min(BSA_i$startyear)
  maxy<-ifelse(is.na(max(BSA_i$endyear))==TRUE,2020,max(BSA_i$endyear))
  BSAy<-seq(from=miny,to=maxy,by=1)
  t_i<-data4%>%filter(ccode==ct)
  ty<-t_i$year
  dy<-ty[which(ty%in%BSAy)]
  if (length(dy)>0){
    regi2<-c(regi2,ct)
  }
}

regi <- hh[-which(hh%in%regi2)]
country[-which(hh%in%ll)]

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits =c(-3.5, 2))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att