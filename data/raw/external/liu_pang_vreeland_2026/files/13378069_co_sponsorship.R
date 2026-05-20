############################################################
# This file analyzes co-sponsorship as outcome
############################################################
library(easypackages)
library(PanelMatch)
library(dplyr)
packages("bpCausal", "panelView", "coda", "countrycode", "RColorBrewer","tidyr")
set.seed(1234)

rm(list=ls())
load("cosponsorship_data.RData") # Load data 
data<-datasave
rm(datasave)
source('plot_function2.R', chdir = TRUE)
source('summary_function.R', chdir = TRUE)

Y <- "co_sp_CHN_all"
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


## plot causal effects
a <- 15

################
## Figure 3(b)
################
eout1 <- effSummary(out1, usr.id =NULL , burn =mm,  cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eout1, type = "eff", x1.pos = 0, y.pos = 0,  xlim = c(-30, 15))
p1.att <-p1.att + scale_y_continuous(limits = c(-0.2, 0.2))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att


##################################
## Figure B2(b): placebo test
##################################
data <- datarun
cc <- unique(data$ccode)
year <- data$year
wartr <- data$swap_dummy_lag1
newtr <- c()

k <- 0   
p <- 5   
for (i in cc){
  newd <- wartr[data$ccode==i]
  yeard <- year[data$ccode==i]
  nn <- length(newd)
  pp <- sum(newd)   
  if (pp>0 & pp!=nn){  
    year1 <- yeard[1] 
    yearn <- yeard[nn] 
    yearm <- year1:yearn 
    gf <- data.frame(yeard, newd)
    names(gf) <- c("yearm", "newd")
    year3 <- data.frame(yearm)
    jkl <- merge(gf, year3, by="yearm", all=TRUE)
    trn <- jkl[,2]
    nwhich <- which(is.na(trn))
    trn[is.na(trn)] <- 99
    nnn <- length(trn)
    nnd <- trn[-1]-trn[-nnn] 
    if (k>0){
      wn <- which(nnd==-1|nnd==98) 
      jj <- length(wn)
      for (j in 1:jj){
        gg <- wn[j]
        bb <- gg+k
        if (bb<=nnn){
          kl<- trn[(gg+1):(gg+k)]
          kl[which(kl==0)] <- 2
          trn[(gg+1):bb] <- kl
        }
        else{
          kl<- trn[(gg+1):nnn]
          kl[which(kl==0)] <- 2
          trn[(gg+1):nnn] <- kl
        }
      }
    }
    if (p>0){
      wng <- which(nnd==1)  
      jjj <- length(wng)
      if (jjj>0){
        for (j in 1:jjj){
          ggg <- wng[j]
          bbb <- ggg-p
          if (bbb>0){
            kl<- trn[bbb:ggg]
            kl[which(kl==0)] <- 0.5
            trn[bbb:ggg] <- kl
          }
          else{
            kl<- trn[1:ggg]
            kl[which(kl==0)] <- 0.5
            trn[1:ggg] <- kl
          }
        }
      }
    }
    trn[nwhich] <- NA
    newd <- trn[!is.na(trn)]
  }
  
  newtr <- c(newtr, newd)
}

nnewtr <- newtr
nnewtr[nnewtr>0] <- 1
data2 <- data.frame(data, nnewtr, newtr)


ND <- "nnewtr"

data3 <-data2[, c(index, Y, ND, X)]


data3 <- data3[order(data3[, index[1]], data[, index[2]]),]

## treatment variable
Dname <- ND
## fixed effect beta
Xname <-X
## unit-level random effects variable
Zname <- X
## time-varying random effects variable
Aname <- X

## two-way re: unit, time, none, both
re <- "both"
set.seed(1234)
out2 <- bpCausal(data = data3, index = index, 
                 Yname = Yname, Dname = Dname, 
                 Xname = Xname, Zname = Zname, Aname = Aname, 
                 re = re, r = r, niter = niter, burn=10000, 
                 xlasso = xlasso, zlasso = 0,
                 alasso = alasso, flasso = flasso)
eout1 <- effSummary(out2, usr.id =NULL , burn =mm,  cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eout1, type = "eff", x1.pos =0,  y.pos = 0, xlim = c(-90, 28))
p2 <- p1.att +geom_vline(xintercept = 5, linetype="dotted",  color = "blue", size=0.8)
p2 <-p2 + scale_y_continuous(limits = c(-0.3, 0.5))
p2 <- p2+theme(axis.text.x = element_text( hjust = 1, size=a))
p2 <- p2 +theme(axis.text.y = element_text( hjust = 1, size=a))
p2

