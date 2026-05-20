############################################################
# This file produces confusion matrices for case selection
############################################################
rm(list=ls())
library(easypackages)
packages("bpCausal", "panelView", "coda", "countrycode", "RColorBrewer","dplyr","ggplot2","caret")


d<-read.csv("ITT_confusion.csv")
d$sum_6<-d$Developing+d$NoBSA_US+d$NoBSA_any+d$Comprehensive_Partner+d$BRI+d$NonDemocracy

c<-c("Developing","NoBSA_US","NoBSA_any","Comprehensive_Partner","BRI","NonDemocracy")
c<-c("Developing_wb","NoBSA_US","NoBSA_any","Comprehensive_Partner","BRI","NonDemocracy") 
com1<-tibble(cond1=as.character(),f1_score=as.numeric())
for (i in 1:(length(c))) {
  c1<-c[i]
  
  d$`Best One`<-ifelse((d[[c1]]==1),1,0)
  d2<-d%>%mutate(`Best One`=as.factor(`Best One`))%>%
    mutate(susceptible=as.factor(susceptible))%>%
    rename("ITT Pattern" =susceptible)
  d2$`Best One`<-as.factor(d2$`Best One`)
  cm <- confusionMatrix(d2$`Best One`, d2$`ITT Pattern`,positive="1")
  precision <- cm$byClass['Pos Pred Value']
  recall <- cm$byClass['Sensitivity']
  f1_score <- 2 * ((precision * recall) / (precision + recall))
  res<-c(c[i],f1_score)
  com1<-rbind(com1,res)
}
##############################################
## Figure E1(b): Low income country condition
##############################################
d2<-d%>%mutate(Developing_wb=as.factor(Developing_wb))%>%
  mutate(susceptible=as.factor(susceptible))%>%
  rename("ITT Pattern" =susceptible)
p<-ggplot(d2, aes(x = Developing_wb, y = `ITT Pattern`, color = `ITT Pattern`)) +
  geom_point(position = position_jitter(width = 0.1, height = 0.1), size = 3.5, alpha = 0.5) +
  geom_text(aes(label = Country), position = position_jitter(width = 0.3, height = 0.3), 
            check_overlap = FALSE, size = 5, vjust = -1, color = "black", alpha = 0.65) +
  scale_color_manual(values = c("1" = "red", "0" = "blue"),
                     labels = c("1" = "Negative and significant", "0" = "Not significant")) +
 labs(x = "Satisfies the Low-income Condition", y = "ITT Pattern") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 0, hjust = 0.5,size=14),
        axis.title.x = element_text(size = 16),  
        axis.title.y = element_text(size = 16), 
        axis.text.y = element_text(size = 14),   
        legend.title = element_text(size = 14),  
        legend.text = element_text(size = 12)  )
false_positive<-d2%>%filter(ITT!=-1 & Developing==1)
p
##############################################
## Figure E1(d): BRI condition
##############################################
d2<-d%>%mutate(BRI=as.factor(BRI))%>%
  mutate(susceptible=as.factor(susceptible))%>%
  rename("ITT Pattern" =susceptible)
p<-ggplot(d2, aes(x = BRI, y = `ITT Pattern`, color = `ITT Pattern`)) +
  geom_point(position = position_jitter(width = 0.1, height = 0.1), size = 3.5, alpha = 0.5) +
  geom_text(aes(label = Country), position = position_jitter(width = 0.3, height = 0.3), 
            check_overlap = FALSE, size = 5, vjust = -1, color = "black", alpha = 0.65) +
  scale_color_manual(values = c("1" = "red", "0" = "blue"),
                     labels = c("1" = "Negative and significant", "0" = "Positive or negative, not significant")) +
 
  labs(x = "Satisfies the BRI Member Condition", y = "ITT Pattern") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 0, hjust = 0.5,size=14),
        axis.title.x = element_text(size = 16),  
        axis.title.y = element_text(size = 16), 
        axis.text.y = element_text(size = 14),   
        legend.title = element_text(size = 14),  
        legend.text = element_text(size = 12)  )

p


##############################################
## Figure 6 and Figure E1(a): No other BSA condition
##############################################
d2<-d%>%mutate(NoBSA_any=as.factor(NoBSA_any))%>%
  mutate(susceptible=as.factor(susceptible))%>%
  rename("ITT Pattern" =susceptible)
p<-ggplot(d2, aes(x = NoBSA_any, y = `ITT Pattern`, color = `ITT Pattern`)) +
  geom_point(position = position_jitter(width = 0.1, height = 0.1), size = 3.5, alpha = 0.5) +
  geom_text(aes(label = Country), position = position_jitter(width = 0.3, height = 0.3), 
            check_overlap = FALSE, size = 5, vjust = -1, color = "black", alpha = 0.65) +
  scale_color_manual(values = c("1" = "red", "0" = "blue"),
                     labels = c("1" = "Negative and significant", "0" = "Positive or negative, not significant")) +
  labs(x = "Satisfies the No BSA with Any Other Country Condition", y = "ITT Pattern") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 0, hjust = 0.5,size=14),
        axis.title.x = element_text(size = 16),  
        axis.title.y = element_text(size = 16),  
        axis.text.y = element_text(size = 14),   
        legend.title = element_text(size = 14),  
        legend.text = element_text(size = 12)  )
p



##############################################
## Figure E1(c): Partnership level condition
##############################################
d2<-d%>%mutate(Comprehensive_Partner=as.factor(Comprehensive_Partner))%>%
  mutate(susceptible=as.factor(susceptible))%>%
  rename("ITT Pattern" =susceptible)
p<-ggplot(d2, aes(x = Comprehensive_Partner, y = `ITT Pattern`, color = `ITT Pattern`)) +
  geom_point(position = position_jitter(width = 0.1, height = 0.1), size = 3.5, alpha = 0.5) +
  geom_text(aes(label = Country), position = position_jitter(width = 0.3, height = 0.3), 
            check_overlap = FALSE, size = 5, vjust = -1, color = "black", alpha = 0.65) +
   scale_color_manual(values = c("1" = "red", "0" = "blue"),
                     labels = c("1" = "Negative and significant", "0" = "Positive or negative, not significant")) +
 
  labs(x = "Satisfies the Comprehensive Partner Condition", y = "ITT Pattern") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 0, hjust = 0.5,size=14),
        axis.title.x = element_text(size = 16), 
        axis.title.y = element_text(size = 16),  
        axis.text.y = element_text(size = 14),  
        legend.title = element_text(size = 14), 
        legend.text = element_text(size = 12)  )

p



