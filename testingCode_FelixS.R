### R script for testing and exploring ###
### NOT intented to be submitted. Instead, submit markdown file!###


### load packages ###
library(tidyverse)
for(p in c("caret","devtools","xts", "dimRed", "foreach","tidyr","fastICA"))
  if (!require(p,character.only=TRUE)) {
    install.packages(p)
    require(p,character.only=TRUE)
  }

if (!require("influxdbr2",character.only=TRUE)) {
  devtools::install_github("mvadu/influxdbr2")
  require("influxdbr2",character.only=TRUE)
}

### load / query sensor data from InflixDB ###
con <- influx_connection(host = "css20.dmz.teco.edu", scheme="http", port=80) 
result <- influx_query_xts(con,db="browser", "select * FROM devicemotion GROUP BY label, subject")

### transform raw data to Data Frame ###
xts_as_table <- function(xts_file){
  # loop over every element of xts_file
  res <- foreach(i=1:length(result),.combine = rbind) %do% {
    # apply split to do windowing: split by seconds
    foreach(s=split(result[i][[1]]$values,"second",k=2),.combine = rbind) %do%{
      # intitialize r
      r={}
      # add subject and label
      r$subject=result[i][[1]]$tags$subject 
      r$label=result[i][[1]]$tags$label
      # extract acceleration coordinates x,y,z
      x=as.numeric(s$accelerationIncludingGravity.x)
      y=as.numeric(s$accelerationIncludingGravity.x)
      z=as.numeric(s$accelerationIncludingGravity.z)
      
      # calculate rmse from x,y,z
      three_d=apply(cbind(x,y,z),FUN=function(x) sqrt(sum(x^2)),MARGIN=1)
      
      # add mobile
      r$mobile=as.vector(first(s$mobile)) 
      # calculate means and add them
      r$mean_x=mean(x, na.rm = T)
      r$mean_y=mean(y, na.rm = T)
      r$mean_z=mean(z, na.rm = T)
      r$mean_3d=mean(three_d, na.rm = T)
      
      # calclate variances and add them
      r$var_x=var(x, na.rm = T)
      r$var_y=var(y, na.rm = T)
      r$var_z=var(z, na.rm = T)
      r$var_3d=var(three_d, na.rm = T)
      
      # calculate ranges and add them
      r$minmax_x=max(x, na.rm = T)-min(x, na.rm = T)
      r$minmax_y=max(y, na.rm = T)-min(y, na.rm = T)
      r$minmax_z=max(z, na.rm = T)-min(z, na.rm = T)
      r$minmax_3d=max(three_d, na.rm = T)-min(three_d, na.rm = T)
      
      # return as df to rbind
      as.data.frame(r)
    }
  }
  return(as.data.frame(res))
}
data = xts_as_table(result)

# inspect data frame dim and basic statistics
dim(data)
summary(data)

### remove testing ###
data <- dplyr::filter(data, label!="testing")

### NA handling ###
# inspect NAs
data_NA <- data[rowSums(is.na(data)) > 0,]
clean_data <- drop_na(data)

### Outlier removal ###
tmp <- clean_data[clean_data$minmax_3d < (mean(clean_data$minmax_3d) + 2* sd(clean_data$minmax_3d)),]
print(dim(clean_data)[1] - dim(tmp)[1])
tmp2 <- tmp[tmp$minmax_3d > (mean(tmp$minmax_3d) - 2* sd(tmp$minmax_3d)),]
print(dim(tmp)[1] - dim(tmp2)[1])
print((dim(clean_data)[1] - dim(tmp2)[1]) / dim(clean_data)[1] * 100)


### Visualizations ###
# histogram of count of labels vs. time
clean_data %>%
  select(subject, label, mobile) %>%
  aggregate(by = list(clean_data$label, clean_data$subject), FUN = length) %>%
  ggplot(aes(x = label,fill= Group.1)) + 
  geom_histogram() + 
  scale_x_log10()

# boxplot of different labels vs. time






######################################
### Exercise 4: Predictor training ###
######################################

# Leave-one-subject out train test split
subjects <- levels(factor(clean_data$subject))
data_subject <- vector(mode = "list", length = nlevels(factor(clean_data$subject)))

for (s in seq(1, nlevels(factor(clean_data$subject)))) {
  data_subject[[s]]<- which(clean_data$subject != subjects[s])
}

# train a Naive Bayes classifier using LOSO-split

train(clean_data[,-c(1,2,3)], clean_data[,"label"], method = "ranger",
      trControl =  trainControl(index = data_subject, summaryFunction = multiClassSummary))

prediction=predict(model,testdata[,-c(1,2,3)])
confusionMatrix(prediction,as.factor(testdata$label))

# gibt es ein Label, welches nur einmalig vorkommt?
tmp <- clean_data %>%
  group_by(label, subject) %>%
  summarise(n = n()) %>%
  ungroup()
table(tmp$subject)

