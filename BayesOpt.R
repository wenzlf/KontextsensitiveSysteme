# function to train randomForest
trainRandomForest.classif <- function(data, part, nfold, dep) {
  ### partition of data
  #
  part.= part
  n = nrow(data)
  nc.<-ncol(data)-1
  #
  train.set = sample(n, size = part.*n)
  test.set = setdiff(1:n, train.set)
  #
  ### defining task
  #
  task.train = makeClassifTask(data = data[train.set,], target = dep)
  task.test = makeClassifTask(data = data[test.set,], target = dep)
  
  # Set parameters
  pc.<- makeParamSet(
    makeIntegerParam("ntree", lower = 1, upper = 100), #number of trees
    makeIntegerParam("nodesize", lower = 15, upper = 30),#depth of tree
    makeIntegerParam("mtry", lower = 1, upper = ncol(data)-1)
  )
  ## learner
  #
  lrn = makeLearner("classif.randomForest")
  ##
  ## resampling
  #
  rdesc = makeResampleDesc("CV",iters=nfold)
  #
  # control object with the defaults:
  mbo.ctrl = makeMBOControl()
  # infill criterion:
  mbo.ctrl = setMBOControlInfill(mbo.ctrl, crit = crit.ei)
  # 15 evaluations of the objective function:
  mbo.ctrl = setMBOControlTermination(mbo.ctrl, max.evals = 15)
  # Design mat
  design.mat = generateRandomDesign(n = 100, par.set = pc.)
  # add the mbo control and design matrix to the mlrMBO tuning function
  ctrl = makeTuneControlMBO(mbo.control = mbo.ctrl, mbo.design = design.mat)
  
  # Start tuning
  tune.pars = tuneParams(learner = lrn, task = task.train, resampling = rdesc,
                         measures = acc, par.set = pc., control = ctrl)
  
  ### calculate model with optimal hyperparameter
  lrn. = setHyperPars(makeLearner("classif.randomForest"), par.vals = tune.pars$x)
  model. = mlr::train(lrn, task.train)
  ### calculate perfomance
  pred.test<-predict(model., task = task.test)
  pred.train<-predict(model., task = task.train)
  print(paste("Performance on training data: ", performance(pred.train, measures =acc)))
  print(paste("Performance on test data: ", performance(pred.test, measures  = acc)))
  
  #return result
  result <- list(model = model., hyperparameter = tune.pars$x,
                 perf.train = performance(pred.train, measures =acc), 
                 performance(pred.test,measures =acc),
                 pred = pred.test)
  return(result)
}






# Method to train Classifcation Tree
trainRPART.classif <- function(data, part, nfold, dep) {
  ### defining task
  #
  # partition of data
  #
  part.= part
  n = nrow(data)
  nc.<-ncol(data)-1
  data[,dep] <- as.factor(data[,dep])
  #
  train.set = sample(n, size = part.*n)
  test.set = setdiff(1:n, train.set)
  #
  task.train = makeClassifTask(data = data[train.set,], target = dep)
  task.test = makeClassifTask(data = data[test.set,], target = dep)
  # Generate the learner
  lrn = makeLearner("classif.rpart")
  # Set parameters
  pc.<- makeParamSet(
    makeIntegerParam("minsplit", lower = 10, upper = 50),#minimal number of observations per leaf 
    makeIntegerParam("maxdepth", lower = 1, upper = 10) # max depth of tree 
  )
  
  ## resampling
  #
  rdesc = makeResampleDesc("CV",iters=nfold)#,reps=5)
  # control object with the defaults:
  ctrl = makeTuneControlGrid()
  
  # Start tuning
  tune.pars <-tuneParams(learner = lrn, task = task.train, resampling = rdesc,
                         measures = list(acc), par.set = pc., control = ctrl)
  
  ### calculate model with optimal hyperparameter
  lrn. = setHyperPars(makeLearner("classif.rpart"), par.vals = tune.pars$x)
  model. = mlr::train(lrn., task.train)
  
  
  ### calculate perfomance
  pred.test<-predict(model., task = task.test)
  pred.train<-predict(model., task = task.train)
  print(paste("Performance on training data: ", performance(pred.train, measures = acc)))
  print(paste("Performance on test data: ", performance(pred.test, measures = acc)))
  
  ### return result
  result = list(model = model., hyperparameter = tune.pars$x, 
                perf.train = performance(pred.train), 
                perf.test = performance(pred.test),
                pred = pred.test)
  
  return(result)
}

# function to create good looking plots
## wrapper Function for rpart.plot
prp <- function(model) {
  model <- model[["model"]][["learner.model"]]
  rpart.plot(model,roundint=FALSE, type = 5, extra = 100, box.palette= c("green3","firebrick1"), shadow.col = "darkgrey",
             fallen.leaves= F)
}