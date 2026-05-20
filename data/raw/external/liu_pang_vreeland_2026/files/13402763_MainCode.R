##################################################################
# This file conducts the main analysis (voting distance as the outcome)
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

#############################################
## Figure 2: Treatment Assignment
#############################################
treat <- panelview(1 ~ swap_dummy_lag1, data = datarun2, index = c("ccode","year"), xlab = "Year", ylab = "Country", axis.lab="time", axis.lab.gap = c(1, 2), main="Treatment Status: Bilateral SWAP with China", by.timing=TRUE,report.missing=TRUE)


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


out1 <- bpCausal(data = datarun, index = index, 
                 Yname = Yname, Dname = Dname, 
                 Xname = Xname, Zname = NULL, Aname = Aname, 
                 re = re, r = r, niter = niter, burn=10000, 
                 xlasso = xlasso, zlasso = zlasso,
                 alasso = alasso, flasso = flasso)

##############################
## Figure B4: Factor Selection
##############################
p1 <- omegaPlot2(out1, oxlim = c(-1, 1), plotlength = 5, labelname = "Factor")


mm <- 15000
sout1 <- coefSummary(out1, burn = mm)


######################################
## Figure B1: Estimated Coefficients
######################################
nameA <-c( Xnam)
data <- sout1$est.beta
data <- data[-1,]

data$id <- dim(data)[1]:1

p <- ggplot(data, aes(mean, id)) 
p <- p + geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50")

p <- p + geom_point() + geom_errorbarh(aes(xmax = ci_u, xmin = ci_l, height = .2))
p <- p + xlab(expression(beta)) + ylab("Covar")
p <- p + scale_y_continuous(expand = c(0, 0), breaks = data$id, labels = nameA, limits = c(min(data$id) -1, max(data$id) + 1))
p <- p + theme_bw(base_size = 15)
p <- p + theme(panel.grid.major = element_blank(),
               panel.grid.minor = element_blank(),
               legend.text = element_text(margin = margin(r = 10, unit = "pt"), size = 12),
               axis.title = element_text(size=12),
               axis.title.x = element_text(size=14,face="bold", margin = margin(t = 8, r = 0, b = 0, l = 0)),
               axis.title.y = element_text(size=14,face="bold", margin = margin(t = 0, r = 8, b = 0, l = 0)),
               axis.text = element_text(color="black", size=8),
               axis.text.x = element_text(size = 14),
               axis.text.y = element_text(size = 14),
               plot.title = element_text(size = 15,
                                         hjust = 0.5,
                                         face="bold",
                                         margin = margin(10, 0, 10, 0)))
p


a <- 15


########################
## Figure 3(a) ATT
########################
eout1 <- effSummary(out1, usr.id =NULL , burn =mm,  cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eout1, type = "eff", x1.pos = 0, y.pos = 0,  xlim = c(-30, 15))
p1.att <-p1.att + scale_y_continuous(limits = c(-1.6, 1.1))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att




tt <- out1$tr.unit.pos

gg <- table(out1$raw.id.tr)

hh <- as.numeric(names(gg))

country <- countrycode(hh, "cown", "country.name")


########################################
# Heterogeneous effects by groups
###########################################
####################################################
## Figure 5(c) and Figure B5(b)
####################################################
## 5(c): Developing countries 
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


## B5(b): Developed Partners
advanced<-c("Canada","United Kingdom","Switzerland","Hungary","Albania",
            "Russia","Ukraine","Belarus","Iceland","South Korea","Japan","Australia","New Zealand")
regi<-countrycode(advanced,"country.name","cown")

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = c(-2,2.5), xlim = c(-90, 28))
p1.att

p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att


####################################################
## Country treatment effect
####################################################
#################
## Figure B3
#################

for (i in 1:length(hh)){
  regi <- hh[i] 
  c<-country[i]
  eouti <- effSummary(out1, usr.id =regi, burn =mm, cumu = FALSE, rela.period = TRUE)
  p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = c(-2.5,2.5), xlim = c(-90, 28))
  
  p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
  p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
  pdf(paste("treatmentEffect_", c, ".pdf", sep = ""))
  plot(p1.att)
  dev.off()
}


#################
## Figure 4
#################
# Make a plot for all ITTS grouped by effect type
ITTall<-tibble(ccode=as.character(),ATT=as.numeric())
for (i in 1:length(hh)){
  regi <- hh[i] 
  eouti <- effSummary(out1, usr.id =regi, burn =mm, cumu = FALSE, rela.period = TRUE)
  res<-tibble(ccode=rep(regi,length(eouti$est.eff$time)),t=eouti$est.eff$time,ATT=eouti$est.eff$estimated_ATT)
  ITTall<-rbind(ITTall,res)
}
ITTall$country<-countrycode(ITTall$ccode,"cown","country.name")

green<-c("Argentina", "Belarus", "Brazil", "Chile", "Indonesia", 
         "Kazakhstan", "Malaysia", "Mongolia", "Morocco", "Singapore", 
         "South Africa", "Suriname", "United Arab Emirates")
yellow<-c("Albania", "Australia", "Egypt", "New Zealand", "Iceland", 
          "South Korea", "Switzerland", "Tajikistan", "Turkey", "Ukraine", "United Kingdom")

blue<-c("Armenia", "Canada", "Hungary", "Zimbabwe", "Laos", "Russia", "Sri Lanka", "Thailand", 
        "Uzbekistan", "Qatar", "Pakistan", "Japan")
purple<-c("Nigeria")


sig_neg<-c(green,purple)
non_sig<-c(yellow,blue)

ITTall<-ITTall%>%mutate(Group = case_when(
  country %in% sig_neg ~ "Negative and Significant",
  country %in% non_sig  ~ "No Significant Effect",
))

ITTall$Group <- factor(ITTall$Group, levels = c("Negative and Significant", 
                                                "No Significant Effect"))

custom_colors <- c(
  "Negative and Significant" = "indianred", 
  "No Significant Effect" = "steelblue"
)

p<-ggplot(data = ITTall, aes(x = t, y = ATT, group = country, color = `Group`)) +
  geom_line(size=1,alpha=0.4) +
  scale_color_manual(values = custom_colors) +  
  theme_minimal() +
  labs(x = "Time", y = "ITT", title = "ITTs Summarized by Effect Heterogeneity") +
  scale_x_continuous(breaks = seq(-5, 15, by = 1),limits = c(-5, 15)) + ylim(-5,5)+
  geom_hline(yintercept = 0, linetype = "dashed", color = "black") +

  annotate("rect", xmin = -5, xmax = 0, ymin = -Inf, ymax = Inf, alpha = 0.2, fill = "gray70") +
  theme_bw()+
  theme(
    legend.text = element_text(size = 10),    
    legend.title = element_text(size = 12)    
  )
p

########################################################
## Figure 5(d) and Figure B5(c): Partnership with China
########################################################
### higher/lower than comprehensive cooperative partnership 
data4<-subset(datarun,swap_dummy_lag1==1)
jj <- tapply(data4$partner_level_lag1, data4$ccode,mean)

#Figure B5(c)
jj <- tapply(data4$partner_level_lag1, data4$ccode,mean)
ll <- as.numeric(names(jj)[which(jj<4)])
regi <- hh[which(hh%in%ll)]

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-2, 3))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

#Figure 5(d)
ll <- as.numeric(names(jj)[which(jj>=4)])
regi <- hh[which(hh%in%ll)]

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-2, 3))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

########################################################
## Figure 5(e) and Figure B5(d): One Belt One Road
########################################################
## Figure 5(e)
data4<-subset(datarun,swap_dummy_lag1==1)
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


## Figure B5(d)
regi<-hh[-which(hh%in%regi2)]

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-3, 2))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

################################################################
## Figure 5(b) and Figure B5(a): With/without other BSA partners
################################################################
## Figure B5(a): Countries with other BSAs with other countries
data4<-subset(datarun,swap_dummy_lag1==1)
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

eouti <- effSummary(out1, usr.id =regi2 , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits = c(-3.5, 2))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

## Figure 5(b): No other BSAs
regi <- hh[-which(hh%in%regi2)]
country[-which(hh%in%ll)]

eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits =c(-3.5, 2))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att

################################################################
## Figure 5(a): GATT for significant cases
################################################################
### States with negative ITTs ###
regi <- c(160, 370, 140, 155, 850, 705, 820, 712, 600, 830, 560, 115, 696,475) 
eouti <- effSummary(out1, usr.id =regi , burn =mm, cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eouti, type = "eff", x1.pos = 0, y.pos = 0, ylim = NULL, xlim = c(-90, 28))
p1.att <-p1.att + scale_y_continuous(limits =c(-3, 3))
p1.att <- p1.att +theme(axis.text.x = element_text( hjust = 1, size=a))
p1.att <- p1.att +theme(axis.text.y = element_text( hjust = 1, size=a))
p1.att


#######################################################################
## Figure E2: Comparison of Prediction Performance of Four Conditions
#######################################################################
d<-read.csv("ITT_confusion.csv")
library(caret)
d$susceptible<-as.factor(d$susceptible)
d$Developing_wb<-as.factor(d$Developing_wb)
d$NoBSA_any<-as.factor(d$NoBSA_any)
d$Comprehensive_Partner<-as.factor(d$Comprehensive_Partner)
d$BRI<-as.factor(d$BRI)
d$NonDemocracy<-as.factor(d$NonDemocracy)

cm1 <- confusionMatrix(d$Developing_wb, d$susceptible,positive="1")
cm3 <- confusionMatrix(d$NoBSA_any, d$susceptible,positive="1")
cm4 <- confusionMatrix(d$Comprehensive_Partner, d$susceptible,positive="1")
cm5 <- confusionMatrix(d$BRI, d$susceptible,positive="1")
cm6 <- confusionMatrix(d$NonDemocracy, d$susceptible,positive="1")

confusion_matrices<-list(cm1,cm3,cm4,cm5)
categories <- c("Low-income", "No BSA with Any", "Comprehensive Partner", "BRI")

metrics_df <- data.frame(
  Category = character(),
  Metric = character(),
  Value = numeric(),
  stringsAsFactors = FALSE
)

for (i in 1:length(confusion_matrices)) {
  cm <- confusion_matrices[[i]]
  category <- categories[i]

  precision <- cm$byClass['Pos Pred Value']
  recall <- cm$byClass['Sensitivity']
  f1_score <- 2 * ((precision * recall) / (precision + recall))
  
  temp_df <- data.frame(
    Category = category,
    Metric = c("Accuracy", "Precision", "Recall", "F1 Score"),
    Value = c(cm$overall['Accuracy'], precision, recall, f1_score)
  )

  metrics_df <- rbind(metrics_df, temp_df)
}
metrics_df<-metrics_df%>%
  mutate(Category=case_when(
    Category=="Low-income" ~"Low-Income Country",
    Category=="No BSA with Any" ~"No Other BSAs",
    Category=="Comprehensive Partner" ~"High-Level Partnership",
    Category=="BRI" ~"MoU Signatory",
  ))
accuracy_df <- metrics_df[metrics_df$Metric == "F1 Score", ]

ordered_categories <- accuracy_df$Category[order(-accuracy_df$Value)]

metrics_df$Category <- factor(metrics_df$Category, levels = ordered_categories)

library(ggsci)
p<-ggplot(metrics_df, aes(x = Category, y = Value, fill = Metric)) +
  geom_bar(stat = "identity", position = position_dodge(), width = 0.7) +
  theme_minimal() +
  labs(title = "Performance Metrics Comparison Across Conditions",
       x = "Category",
       y = "Metric Value") +
  scale_fill_npg()+
  theme(axis.text.x = element_text(angle = 30, hjust = 1),
        plot.title = element_text(hjust = 0.5))
p


##############################
### Figure B2(a): Placebo test
##############################

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

re <- "both"

out2 <- bpCausal(data = data3, index = index, 
                 Yname = Yname, Dname = Dname, 
                 Xname = Xname, Zname = Zname, Aname = Aname, 
                 re = re, r = r, niter = niter, burn=10000, 
                 xlasso = xlasso, zlasso = 0,
                 alasso = alasso, flasso = flasso)

eout1 <- effSummary(out2, usr.id =NULL , burn =mm,  cumu = FALSE, rela.period = TRUE)
p1.att <- effPlot(eout1, type = "eff", x1.pos =0,  y.pos = 0, xlim = c(-90, 28))
p2 <- p1.att +geom_vline(xintercept = 5, linetype="dotted",  color = "blue", size=0.8)
p2 <-p2 + scale_y_continuous(limits = c(-2.0, 1.5))
p2 <- p2+theme(axis.text.x = element_text( hjust = 1, size=a))
p2 <- p2 +theme(axis.text.y = element_text( hjust = 1, size=a))
p2

