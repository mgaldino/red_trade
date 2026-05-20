###################################################
## This file run model with loans as the treatment
###################################################
rm(list=ls())
set.seed(123)
## load packages
library(easypackages)
library(PanelMatch)
library(dplyr)
packages("bpCausal", "panelView", "coda", "countrycode", "RColorBrewer","WDI")

load("loanasT_data.RData")


source('plot_function2.R', chdir = TRUE)
source('summary_function.R', chdir = TRUE)

data$distance_idealpoint_cn<- exp(data$distance_idealpoint_chnlog)-1
data$distance_idealpoint_us_lognew <-  log(data$distance_idealpoint_usa+0.001)
data$distance_idealpoint_us_lag <- exp(data$distance_idealpoint_usalog_lag1)-1
data$distance_idealpoint_cn_lognew <- log(data$distance_idealpoint_cn+0.001)
data$distance_idealpoint_us_lag_lognew <- log(data$distance_idealpoint_us_lag+0.001)



Y <- "distance_idealpoint_cn_lognew"
D <- 'drawn_lag1'
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
tapply(datarun$drawn_lag1, datarun$ccode,sum) 

data2 <- subset(datarun,drawn_lag1==1)

data2$year <- as.integer(data2$year)


datarun2 <- datarun
datarun2$year <- datarun$year-1 

##################
## Figure D1 
##################
datarun3<-datarun%>%filter(year>=1993)
treat <- panelview(1 ~ drawn_lag1, data = datarun3, index = c("ccode","year"), xlab = "Year", ylab = "Country", axis.lab="time", axis.lab.gap = c(1, 2), main="Treatment Status: Bilateral SWAP with China", by.timing=TRUE)

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
sout1 <- coefSummary(out1, burn = mm)

nameA <-c( Xnam)
data <- sout1$est.beta
data <- data[-1,]

data$id <- dim(data)[1]:1

a <- 15

###############
## Figure D2
###############
eout1 <- effSummary(out1, usr.id =NULL , burn =mm,  cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eout1, type = "eff", x1.pos = 0, y.pos = 0,  xlim = c(-30, 15))
p1.att <-p1.att + scale_y_continuous(limits = c(-2, 2.5))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

tt <- out1$tr.unit.pos
gg <- table(out1$raw.id.tr)

hh <- as.numeric(names(gg))

country <- countrycode(hh, "cown", "country.name")

#############################################
## Figure D4(a):Partner level with China
#############################################
data4<-subset(datarun,drawn_lag1==1)
jj <- tapply(data4$partner_level_lag1, data4$ccode,mean)

#Not comprehensive cooperation partner or above
ll <- as.numeric(names(jj)[which(jj<4)])
regi <- hh[which(hh%in%ll)]
eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-3, 3))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att


#Comprehensive cooperation partner or above
ll <- as.numeric(names(jj)[which(jj>=4)])
regi <- hh[which(hh%in%ll)]
eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-2, 3))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

#############################################
## Figure D4(c):Regime type
#############################################
## democracy
data4<-subset(datarun,drawn_lag1==1)

jj<-tapply(data4$v2x_polyarchy_lag1,data4$ccode,mean)

ll <- as.numeric(names(jj)[which(jj >0.5)])

regi <- hh[which(hh%in%ll)]
eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-5, 5))

p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

## non-democracy
data4<-subset(datarun,drawn_lag1==1)
jj<-tapply(data4$v2x_polyarchy_lag1,data4$ccode,mean)
ll <- as.numeric(names(jj)[which(jj <=0.5)])

regi <- hh[which(hh%in%ll)]
eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-5,5))

p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

#############################################
## Figure D3:Developing vs developed economies
#############################################
# Developing country

regi<-c(1:17,19:23)

eouti <- effSummary(out1, usr.id =hh[regi] , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-2.5,2.5))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

# Developed country
regi<-c(18,24) 
eouti <- effSummary(out1, usr.id =hh[regi] , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-2.5,2.5))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att
#############################################
## Figure D4(b): OBOR
#############################################
# Signed OBOR MoU
data4<-subset(datarun,drawn_lag1==1)
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
p1.att <-p1.att + scale_y_continuous(limits = c(-3, 3))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att


# Did not sign OBOR MoU
regi<-hh[-which(hh%in%regi2)]
eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-3, 3))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att


