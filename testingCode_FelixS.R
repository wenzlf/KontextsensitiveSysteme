### R script for testing and exploring ###
### NOT intented to be submitted. Instead, submit markdown file!###


### load packages ###
library(tidyverse)
library(MLmetrics)
library(ellipse)

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
# Make sure to be in the KIT Network!!!! Use VPN!!!
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
# version 1: mean +/- 2*sd
# tmp <- clean_data[clean_data$minmax_3d < (mean(clean_data$minmax_3d) + 2* sd(clean_data$minmax_3d)),]
# print(dim(clean_data)[1] - dim(tmp)[1])
# tmp2 <- tmp[tmp$minmax_3d > (mean(tmp$minmax_3d) - 2* sd(tmp$minmax_3d)),]
# print(dim(tmp)[1] - dim(tmp2)[1])
# print((dim(clean_data)[1] - dim(tmp2)[1]) / dim(clean_data)[1] * 100)
clean_data <- clean_data[clean_data$minmax_3d < (mean(clean_data$minmax_3d) + 2* sd(clean_data$minmax_3d)),]
clean_data <- clean_data[clean_data$var_3d < (mean(clean_data$var_3d) + 2* sd(clean_data$var_3d)),]
clean_data <- clean_data[clean_data$mean_3d < (mean(clean_data$mean_3d) + 2* sd(clean_data$mean_3d)),]


# version 2: IQR
IQR.outliers <- function(data) {
  Q3<-quantile(data,0.75, na.rm = T)
  Q1<-quantile(data,0.25, na.rm = T)
  IQR<-(Q3-Q1)
  left<- Q1-(1.5*IQR)
  right<- Q3+(1.5*IQR)
  print(sum(data < left))
  print(sum(data > right))
  index <- data < left | data>right
  return(which(index))
}
IQR.outliers(data$minmax_3d)


### Visualizations ###
# histogram of count of labels vs. time
clean_data %>%
  select(subject, label, mobile) %>%
  aggregate(by = list(clean_data$label, clean_data$subject), FUN = length) %>%
  ggplot(aes(x = label,fill= Group.1)) + 
  geom_histogram() + 
  scale_x_log10()

# boxplot of different labels vs. time
cols=c(7,11,15)
caret::featurePlot(x=clean_data[,cols], y=factor(clean_data$label), plot="box", auto.key = list(columns = 2))

# scaling
prep <- preProcess(clean_data[,-c(1,2,3)],method=c("scale","center"),n.comp=3)

clean_data <- cbind(clean_data[,c(1,2,3)],predict(prep,clean_data[,-c(1,2,3)]))




######################################
### Exercise 4: Predictor training ###
######################################

# Leave-one-subject out train test split
subjects <- levels(factor(clean_data$subject))
data_subject <- vector(mode = "list", length = nlevels(factor(clean_data$subject)))

for (s in seq(1, nlevels(factor(clean_data$subject)))) {
  data_subject[[s]]<- which(clean_data$subject != subjects[s])
}

#TODO: Tunegrid for train function

# train a Naive Bayes classifier using LOSO-split
train(clean_data[,-c(1,2,3)], clean_data[,"label"], method = "naive_bayes",
      trControl =  trainControl(index = data_subject, summaryFunction = multiClassSummary))

prediction=predict(model,testdata[,-c(1,2,3)])
confusionMatrix(prediction,as.factor(testdata$label))

# gibt es ein Label, welches nur einmalig vorkommt?
tmp <- clean_data %>%
  group_by(label, subject) %>%
  summarise(n = n()) %>%
  ungroup()
table(tmp$label)


# # Backlog: using resampling?? 
# clean_data %>%
#   group_by(label, subject) %>%
#   summarise(N = n()) %>%
#   spread(key = label, value = N)


# use different train control functions:
# 1. pre-defined function
trainControl1 <- trainControl(index = data_subject, summaryFunction = multiClassSummary,
                              verboseIter = T)
# 2. own function: 
trainControl2 <- trainControl(method = "LGOCV", summaryFunction = multiClassSummary, 
                              classProbs = T)


# used methods (accuracy): naive_bayes (0.71), ranger (0.76), svmRadial (0.58), svmLinear (0.65), 
# xgbTree (0.77: eta = 0.3, max_depth = 2, colsample_bytree = 0.8, subsample = 0.5, nrounds = 50)
model_naiveBayes <- train(clean_data[,-c(1,2,3)], clean_data[,"label"], method = "naive_bayes",
      trControl =  trainControl1)

model_ranger <- train(clean_data[,-c(1,2,3)], clean_data[,"label"], method = "ranger",
                          trControl =  trainControl1)

#TODO add more feature manually to improve your results

# Select best feature using a wrapper using carets Recursive Feature Elimination
# define the control using a random forest selection function
# treebagFuncs, nbFuncs, rfFuncs, caretFuncs
control <- rfeControl(functions=nbFuncs, method="cv", number=10)
# run the RFE algorithm
results <- rfe(clean_data[,-c(1,2,3)], factor(clean_data[,"label"]), sizes = c(1:12), rfeControl=control)
# summarize the results
print(results)  
# list the chosen features
predictors(results)
# plot the results
plot(results, type=c("g", "o"))  
