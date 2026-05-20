############################################################
# This file produces Visualization plots
############################################################



library(rio)
library(dplyr)
library(network)
library(igraph)
library(WDI)
library(countrycode)
library(PanelMatch)
library(haven)
library(ggplot2)
library(viridis)
library(priceR)
library(ggraph)

BSAdata <- import_list("Data_SWAPNet_panel_202207.xlsx") 

BSAglist<-list()
BSAnetlist<-list()

for (i in 2:14){
  dat<-BSAdata[[i]]
  m1 <- dat %>%       
    distinct(ISO3_A) %>%
    rename(label = ISO3_A)
  m2<-dat%>%
    distinct(ISO3_B)%>%
    rename(label=ISO3_B)
  BSAnodes <- full_join(m1,m2, by = "label")
  BSAedges <-dat%>%    
    select(ISO3_A,ISO3_B)
  BSAglist[[i]]<-graph_from_data_frame(d = BSAedges, vertices =BSAnodes, directed = FALSE)
  BSAnetlist[[i]]<-network(BSAedges, matrix.type = "edgelist", ignore.eval = TRUE,directed=FALSE)
  print(paste0("finished working on i= ",i))
}

BSAglist<-BSAglist[-1]
BSAnetlist<-BSAnetlist[-1]
###############
## Figure 1 (a)
###############
collector<-c()
rest<-c()
total<-c()
for (i in 1:12){
  x<-as.data.frame(degree(BSAglist[[i]]))
  colnames(x)<-"degree"
  x$year<-i+2007
  x$country<-rownames(x)
  rownames(x)<-1:nrow(x)
  
  totres<-ecount(BSAglist[[i]])-(x[x$country=="CHN",]$degree)
  totres<-tibble(year=i+2007,totres=totres)
  
  tot<-tibble(year=i+2007,tot=ecount(BSAglist[[i]]))
  
  collector<-rbind(collector,x)
  rest<-rbind(rest,totres)
  total<-rbind(total,tot)
}
#China
China<-collector%>%filter(country=="CHN")%>%select(year,degree)
#US
US<-collector%>%filter(country=="USA")%>%select(year,degree)

colnames(total)<-c("year","bsa")
total$"BSA Signatory"<-"Total"
colnames(rest)<-c("year","bsa")
rest$"BSA Signatory"<-"Rest of the World"
colnames(China)<-c("year","bsa")
China$"BSA Signatory"<-"China"
colnames(US)<-c("year","bsa")
US$"BSA Signatory"<-"US"
d<-rbind(total,rest,China)

p1<-d%>%
  ggplot( aes(x=year, y=bsa, group=`BSA Signatory`, color=`BSA Signatory`, linetype=`BSA Signatory`)) +
  geom_line(alpha=1,size=1.2)+
  scale_x_continuous(breaks = seq(2008,2019,2))+
  scale_colour_manual(values=c("orange", "gray60", "black"))+
  theme(panel.grid.major = element_blank(), 
        panel.grid.minor = element_blank(),panel.background = element_blank(), 
        axis.line = element_line(colour = "black"),
        legend.text = element_text(size=13),legend.title=element_text(size=15),
        axis.text=element_text(size=12),
        axis.title=element_text(size=14))+
  ylab("Number of BSAs")+xlab("Year")




###############
## Figure 1 (b)
###############
load("currency_converted.RData")
i<-13

d<-collector[[i]]
  
  m1 <- d %>%         
    distinct(ISO3_A) %>%
    rename(label = ISO3_A)
  m2<-d%>%
    distinct(ISO3_B)%>%
    rename(label=ISO3_B)
  BSAnodes <- full_join(m1,m2, by = "label")
  BSAedges <-d%>%     
    select(ISO3_A,ISO3_B,total_dollar)%>%
    rename(weight=total_dollar)
  g<-graph_from_data_frame(d = BSAedges, vertices =BSAnodes, directed = FALSE)
  
  cet<-degree(g)
  V(g)$size <- cet*0.5+3
  V(g)$label.cex=cet*0.01+0.5
  
  E(g)$weight<-E(g)$weight/1000+0.1
p1<-ggraph(g,  layout = 'lgl') +
    geom_edge_arc(color="gray", strength = 0.2,aes(width =E(g)$weight),alpha=0.5) + 
    geom_node_point(color="orange", aes(size = cet*1.2+1)) +     
    geom_node_text(aes(label = V(g)$name), size=cet*0.3+3, color="steelblue", repel=T) +
    theme_void()+theme(legend.position = "none")


