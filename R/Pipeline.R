##########################################################################################################
##################### FULL VARIABLE SELECTION ANALYSIS FOR IMPACT GENETIC DATA ###########################
##########################################################################################################

#' OncoCast
#'
#' This functions let's the user select one or multiple statistical learning algorithms (penalized regression).
#' This is intended for survival data, and the mehods can handle left truncated survival data with binary predictors
#' (mutation data).
#' The inputed data should be a data frame with columns representing the variables of interest while the rows should correspond to patients.
#' All methods selected will all return a list of length equal to the number of crossvalidation performed,
#' including the predicted risk score at each cross validation for all the patients falling in the test set.
#' @param data Data frame with variables as columns and patients as rows. Must have no missing data and should contain only the outcome and the predictors to be used.
#' We recommend the time variables to use the month unit.
#' @param formula A survival formula with the names of the variables to be used in the data frame provided in the first argument.
#'  eg : Surv(time,status)~. or Surv(time1,time2,status)~. (Note all the variable available will be used regardless of the right
#'  side of the formula).
#' @param method Character vector of the names of the method(s) to be used, options are : 1) LASSO ("LASSO") 2) Ridge ("RIDGE")
#'  3) Elastic Net ("ENET"). Default is all.
#' @param runs Number of cross validation iterations to be performed. Default is 100.
#' @param sampling The method use for sampling, options are bootstrapping ("boot") and cross-validation ("cv").
#' Default is cross-validation.
#' @param nonPenCol Name of variables you do not with to penalize (available only for LASSO, RIDGE and ENET methods). Default is NULL.
#' @param cores If you wish to run this function in parallel set the number of cores to be used to be greater than 1. Default is 1.
#' CAUTION : Overloading your computer can lead to serious issues, please check how many cores are available on your machine
#' before selecting an option!
#' @param pathResults String of where the users wishes to output the results. Default is current directory.
#' @param studyType String that will be the prefix to the name of the outputed results. Default is empty.
#' @param save Boolean value : Default is TRUE, the results will be saved with the specified name in the specified path. If FALSE the results
#' will be returned directly from the function and won't be saved.
#' @return CI : For each iteration the concordance index of the generated model will be calculated on the testing set
#' @return fit : For LASSO, RIDGE and ENET methods return the refitted cox proportional hazard model with the beta coefficients found
#' in the penalized regression model.
#' @return predicted : The predicted risk for all the patients in the testing set.
#' @return means : The mean value of the predictors that were not shrunken to zero in the penalized regression method.
#' @return method : The name of the method that was used to generate the output.
#' @return data : The data used to fit the model (available only in the first element of the list).
#' @keywords Selection, penalized regression
#' @export
#' @examples library(OncoCast)
#' test <- OncoCast(data=survData,formula=Surv(time,status)~.,
#'                           method=c("LASSO"),
#'                           runs = 25,cores = 1,sampling = "cv",
#'                           pathResults = "./Test/",studyType = "ExampleRun",save=F)
#' @import survival
#' @import penalized
#' @import foreach
#' @import doParallel
#' @import party
#' @import stats


OncoCast <- function(data,formula, method = c("LASSO","RIDGE","ENET"),
                     runs = 100,
                     sampling = "cv",
                     cores = 1,
                     nonPenCol = NULL,
                     pathResults = "",studyType = "",save = T){

  # Missingness
  if(anyNA(data)){
    stop("ERROR : Missing data is not allowed at this time, please remove or impute missing data.")
  }

  # check arguments
  if( anyNA(match(method,c("LASSO","ENET","RIDGE"))) ){stop("ERROR : The method you have selected is not available.")}

  if(!(sampling %in% c("cv","boot"))){
    stop("ERROR : This sampling method is not available. OPTIONS : 'cv' or 'boot'.")
  }

  if(runs < 0){stop("The number of cross-validation/bootstraps MUST be positive.")}
  else if(runs < 50){warning("We do not recommend using a number of cross-validation/bootstraps lower than 50.")}

  ### Prepare cores
  cl <- makeCluster(cores)
  registerDoParallel(cl)

  ##### generate empty output objects #####
  LASSO <- NULL
  ENET <- NULL
  RIDGE <- NULL


  # appropriate formula
  survFormula <- as.formula(formula)
  survResponse <- survFormula[[2]]

  if(!length(as.list(survResponse)) %in% c(3,4)){
    stop("ERROR : Response must be a 'survival' object with 'Surv(time, event)' or 'Surv(time1, time2, event)'.")
  }
  ### reprocess data
  if(length(as.list(survResponse)) == 3){
    colnames(data)[match(as.list(survResponse)[2:3],colnames(data))] <- c("time","status")
    LT = FALSE
  }
  if(length(as.list(survResponse)) == 4){
    colnames(data)[match(as.list(survResponse)[2:4],colnames(data))] <- c("time1","time2","status")
    LT = TRUE
  }


  print("Data check performed, ready for analysis.")

  ########## LASSO #############
  final.lasso <- list()
  if("LASSO" %in% method) {
    print("LASSO SELECTED")
    LASSO <- foreach(run=1:runs) %dopar% {

      ### BUILD TRAINING AND TESTING SET ###
      set.seed(run)
      print(paste("Run : ", run,sep=""))
      # split data
      if(sampling == "cv"){
        rm.samples <- sample(1:nrow(data), ceiling(nrow(data)*1/3),replace = FALSE)
        train <- data[-rm.samples,]
        test <- data[rm.samples,]}

      if(sampling == "boot"){
        rm.samples <- sample(1:nrow(data), nrow(data),replace = TRUE)
        train <- data[rm.samples,]
        test <- data[-rm.samples,]
      }

      # make new survival objects
      if(LT) {
        trainSurv <- with(train,Surv(time1,time2,status))
        testSurv <- with(test,Surv(time1,time2,status))
        if(is.null(nonPenCol)){
        opt <- try(optL1(trainSurv,data = train,penalized = train[,4:ncol(train)],fold = 5,trace=FALSE))}
        else{
          noPen.index <- match(nonPenCol,colnames(train))
          noPen.index.pen <-c(1:3,noPen.index)
          opt <- try(optL1(trainSurv,data = train,penalized = train[,-noPen.index.pen],
                           unpenalized = train[,nonPenCol],fold = 5,trace=FALSE))
        }
      }

      else {
        trainSurv <- with(train,Surv(time,status))
        testSurv <- with(test,Surv(time,status))
        if(is.null(nonPenCol)){
        opt <- try(optL1(trainSurv,data = train,penalized = as.matrix(train[,3:ncol(train)]),fold = 5,trace=FALSE))}
        else{
          noPen.index <- match(nonPenCol,colnames(train))
          noPen.index.pen <-c(1,2,noPen.index)
          opt <- try(optL1(trainSurv,data = train,penalized = train[,-noPen.index.pen],
                           unpenalized = train[,nonPenCol],fold = 5,trace=FALSE))
        }
      }


      if(typeof(opt) == "list" && length(coefficients(opt$fullfit)) != 0){
        optimal.coefs <- coefficients(opt$fullfit)
        coefs.left <- names(coefficients(opt$fullfit))
        if(LT) lasso.formula <- as.formula(paste("Surv(time1,time2,status) ~ ",paste(coefs.left, collapse= "+")))
        if(!LT) lasso.formula <- as.formula(paste("Surv(time,status) ~ ",paste(coefs.left, collapse= "+")))
        # Refit model with the corresponding coefficients
        lasso.fit <- coxph(lasso.formula, data=train,init=optimal.coefs,iter=0)
        # save what you need to save
        if(sampling == "cv"){
          CI <- as.numeric(survConcordance(testSurv ~predict(lasso.fit, newdata=test),
                                           test)$concordance)}
        if(sampling=="boot"){
          CI <- 0.632*as.numeric(survConcordance(testSurv ~predict(lasso.fit, newdata=test),
                                                 test)$concordance) +
            0.368*as.numeric(survConcordance(trainSurv ~predict(lasso.fit, newdata=train),
                                             train)$concordance)}

        predicted <- rep(NA,nrow(data))
        names(predicted) <- rownames(data)
        predicted[match(names(predict(lasso.fit, newdata=test)),names(predicted))] <- as.numeric(predict(lasso.fit, newdata=test))

        if(LT) {coefs <- rep(NA,ncol(data)-3); names(coefs) <- colnames(data)[4:ncol(data)]}
        if(!LT) {coefs <- rep(NA,ncol(data)-2); names(coefs) <- colnames(data)[3:ncol(data)]}
        coefs[match(coefs.left,names(coefs))] <- summary(lasso.fit)$coefficients

        final.lasso$CI <- CI
        final.lasso$fit <- coefs
        final.lasso$predicted <- predicted
        final.lasso$data <- NULL
        final.lasso$means <- lasso.fit$means
      }
      else{
        final.lasso <- NULL
      }
      return(final.lasso)
    }

    if(save){
      save(LASSO,file = paste0(pathResults,studyType,"_",sampling,"_LASSO.Rdata"))
      LASSO <- NULL}
  }

  ##### RIDGE #####

  final.ridge <- list()
  if("RIDGE" %in% method) {
    print("RIDGE SELECTED")
    RIDGE <- foreach(run=1:runs) %dopar% {

      ### BUILD TRAINING AND TESTING SET ###
      set.seed(run)
      print(paste("Run : ", run,sep=""))
      # split data
      if(sampling == "cv"){
        rm.samples <- sample(1:nrow(data), ceiling(nrow(data)*1/3),replace = FALSE)
        train <- data[-rm.samples,]
        test <- data[rm.samples,]}

      if(sampling == "boot"){
        rm.samples <- sample(1:nrow(data), nrow(data),replace = TRUE)
        train <- data[rm.samples,]
        test <- data[-rm.samples,]
      }


      # make new survival objects
      if(LT) {
        trainSurv <- with(train,Surv(time1,time2,status))
        testSurv <- with(test,Surv(time1,time2,status))
        if(is.null(nonPenCol)){
          opt <- try(optL1(trainSurv,data = train,penalized = train[,4:ncol(train)],fold = 5,trace=FALSE))}
        else{
          noPen.index <- match(nonPenCol,colnames(train))
          noPen.index.pen <-c(1:3,noPen.index)
          opt <- try(optL1(trainSurv,data = train,penalized = train[,-noPen.index.pen],
                           unpenalized = train[,nonPenCol],fold = 5,trace=FALSE))
        }
      }

      else {
        trainSurv <- with(train,Surv(time,status))
        testSurv <- with(test,Surv(time,status))
        if(is.null(nonPenCol)){
          opt <- try(optL1(trainSurv,data = train,penalized = train[,3:ncol(train)],fold = 5,trace=FALSE))}
        else{
          noPen.index <- match(nonPenCol,colnames(train))
          noPen.index.pen <-c(1,2,noPen.index)
          opt <- try(optL1(trainSurv,data = train,penalized = train[,-noPen.index.pen],
                           unpenalized = train[,nonPenCol],fold = 5,trace=FALSE))
        }
      }

      if(typeof(opt) == "list" && length(coefficients(opt$fullfit)) != 0){
        # get optimal coefficients
        optimal.coefs <- coefficients(opt$fullfit)
        coefs.left <- names(coefficients(opt$fullfit))
        if(LT) {ridge.formula <- as.formula(paste("Surv(time1,time2,status) ~ ",paste(coefs.left, collapse= "+")))}
        else {ridge.formula <- as.formula(paste("Surv(time,status) ~ ",paste(coefs.left, collapse= "+")))}

        # Refit model with the corresponding coefficients
        ridge.fit <- coxph(ridge.formula, data=train,init=optimal.coefs,iter=0)

        # save what you need to save
        if(sampling == "cv"){
          CI <- as.numeric(survConcordance(testSurv ~predict(ridge.fit, newdata=test),
                                           test)$concordance)}
        if(sampling=="boot"){
          CI <- 0.632*as.numeric(survConcordance(testSurv ~predict(ridge.fit, newdata=test),
                                                 test)$concordance) +
            0.368*as.numeric(survConcordance(trainSurv ~predict(ridge.fit, newdata=train),
                                             train)$concordance)}

        predicted <- rep(NA,nrow(data))
        names(predicted) <- rownames(data)
        predicted[match(names(predict(ridge.fit, newdata=test)),names(predicted))] <- as.numeric(predict(ridge.fit, newdata=test))

        if(LT) {coefs <- rep(NA,ncol(data)-3); names(coefs) <- colnames(data)[4:ncol(data)]}
        if(!LT) {coefs <- rep(NA,ncol(data)-2); names(coefs) <- colnames(data)[3:ncol(data)]}
        coefs[match(coefs.left,names(coefs))] <- summary(ridge.fit)$coefficients

        final.ridge$CI <- CI
        final.ridge$fit <- coefs
        final.ridge$predicted <- predicted
        final.ridge$means <- ridge.fit$means
        if(run == 1){
          final.ridge$method <- "RIDGE"
          final.ridge$data <- data}
      }
      else{
        final.ridge <- NULL
      }
      return(final.ridge)
    }
    if(save){
      save(RIDGE,file = paste0(pathResults,studyType,"_",sampling,"_RIDGE.Rdata"))
      RIDGE <- NULL}
  }

  #### LASSO ENET #####

  final.enet <- list()
  if("ENET" %in% method) {
    print("ENET SELECTED")
    ENET <- foreach(run=1:runs) %dopar% {

      ### BUILD TRAINING AND TESTING SET ###
      set.seed(run)
      print(paste("Run : ", run,sep=""))
      # split data
      if(sampling == "cv"){
        rm.samples <- sample(1:nrow(data), ceiling(nrow(data)*1/3),replace = FALSE)
        train <- data[-rm.samples,]
        test <- data[rm.samples,]}

      if(sampling == "boot"){
        rm.samples <- sample(1:nrow(data), nrow(data),replace = TRUE)
        train <- data[rm.samples,]
        test <- data[-unique(rm.samples),]
      }

      if(LT) {
        trainSurv <- with(train,Surv(time1,time2,status))
        testSurv <- with(test,Surv(time1,time2,status))
        if(is.null(nonPenCol)){
          opt.alpha <- try(optL2(trainSurv,data = train,penalized = train[,4:ncol(train)],
                                 unpenalized = ~0,fold=5,model = "cox",trace = FALSE),silent=T)
          alpha.final <- try(opt.alpha$lambda/8,silent=T)
          opt <- try(optL1(trainSurv,data = train,penalized = train[,4:ncol(train)],
                           unpenalized = ~0,fold=5,lambda2 = alpha.final,model = "cox",trace = FALSE),silent=T)}
        else{
          noPen.index <- match(nonPenCol,colnames(train))
          noPen.index.pen <-c(1:3,noPen.index)
          opt.alpha <- try(optL2(trainSurv,data = train,penalized = train[,-noPen.index.pen],
                                 unpenalized = train[,nonPenCol],fold=5,model = "cox",trace = FALSE),silent=T)
          alpha.final <- try(opt.alpha$lambda/8,silent=T)
          opt <- try(optL1(trainSurv,data = train,penalized = train[,-noPen.index.pen],
                           unpenalized = train[,nonPenCol],fold = 5,lambda2 = alpha.final,trace=FALSE),silent=T)
        }
      }

      else {
        trainSurv <- with(train,Surv(time,status))
        testSurv <- with(test,Surv(time,status))
        if(is.null(nonPenCol)){
          opt.alpha <- try(optL2(trainSurv,data = train,penalized = train[,3:ncol(train)],
                                 unpenalized = ~0,fold=5,model = "cox",trace = FALSE),silent=T)
          alpha.final <- try(opt.alpha$lambda/8,silent=T)
          opt <- try(optL1(trainSurv,data = train,penalized = train[,3:ncol(train)],
                           unpenalized = ~0,fold=5,lambda2 = alpha.final,model = "cox",trace = FALSE),silent=T)}
        else{
          noPen.index <- match(nonPenCol,colnames(train))
          noPen.index.pen <-c(1:2,noPen.index)
          opt.alpha <- try(optL2(trainSurv,data = train,penalized = train[,-noPen.index.pen],
                                 unpenalized = train[,nonPenCol],fold=5,model = "cox",trace = FALSE),silent=T)
          alpha.final <- try(opt.alpha$lambda/8,silent=T)
          opt <- try(optL1(trainSurv,data = train,penalized = train[,-noPen.index.pen],
                           unpenalized = train[,nonPenCol],fold = 5,lambda2 = alpha.final,trace=FALSE),silent=T)
        }
      }


      if(typeof(opt) == "list" && length(coefficients(opt$fullfit)) != 0){
        optimal.coefs <- coefficients(opt$fullfit)
        coefs.left <- names(coefficients(opt$fullfit))
        if(LT) lasso.formula <- as.formula(paste("Surv(time1,time2,status) ~ ",paste(coefs.left, collapse= "+")))
        if(!LT) lasso.formula <- as.formula(paste("Surv(time,status) ~ ",paste(coefs.left, collapse= "+")))
        # Refit model with the corresponding coefficients
        lasso.fit <- coxph(lasso.formula, data=train,init=optimal.coefs,iter=0)
        # save what you need to save
        if(sampling == "cv"){
          CI <- as.numeric(survConcordance(testSurv ~predict(lasso.fit, newdata=test),
                                           test)$concordance)}
        if(sampling=="boot"){
          CI <- 0.632*as.numeric(survConcordance(testSurv ~predict(lasso.fit, newdata=test),
                                                 test)$concordance) +
            0.368*as.numeric(survConcordance(trainSurv ~predict(lasso.fit, newdata=train),
                                             train)$concordance)}

        predicted <- rep(NA,nrow(data))
        names(predicted) <- rownames(data)
        predicted[match(names(predict(lasso.fit, newdata=test)),names(predicted))] <- as.numeric(predict(lasso.fit, newdata=test))

        if(LT) {coefs <- rep(NA,ncol(data)-3); names(coefs) <- colnames(data)[4:ncol(data)]}
        if(!LT) {coefs <- rep(NA,ncol(data)-2); names(coefs) <- colnames(data)[3:ncol(data)]}
        coefs[match(coefs.left,names(coefs))] <- summary(lasso.fit)$coefficients

        final.enet$CI <- CI
        final.enet$fit <- coefs
        final.enet$predicted <- predicted
        final.enet$data <- NULL
        final.enet$alphas <- alpha.final
        final.enet$means <- lasso.fit$means
      }
      else{
        final.enet <- NULL
      }
      return(final.enet)
    }
    if(save){
      save(ENET,file = paste0(pathResults,studyType,"_",sampling,"_ENET.Rdata"))
      ENET <- NULL}
  }

  ################

  stopCluster(cl)
  OUTPUT <- list()
  if(!is.null(LASSO)){OUTPUT$LASSO <- LASSO}
  if(!is.null(RIDGE)){OUTPUT$RIDGE <- RIDGE}
  if(!is.null(ENET)){OUTPUT$ENET <- ENET}

  if(!is.null(OUTPUT)){
    #OUTPUT$data <- data
    return(OUTPUT)}
  else{return(0)}

}

# rm(list=ls())
# setwd("~/RonglaiAndy/EarlyStageNSCLC/data/")
# data <- read.csv("EarlyStageMut.csv",row.names = 1)
# genes <- colnames(data)[-c(1:2)]
# genes.rm <- names(which(apply(data[,genes],2,sum)<=4))
# data <- read.csv("MutClin.csv",row.names = 1)
# data <- data[,-match(genes.rm,colnames(data))]
#
# library(OncoCast)
# test <- OncoCast(data,formula = Surv(time,status)~.,method = c("LASSO"),
#                  runs = 20,cores = 1,
#                  pathResults = "../results/",
#                  studyType = "EarlyStage_WithClin",save=F)

# rm(list=ls())
# setwd("~/RonglaiAndy/EarlyStageNSCLC/results/")
# load("EarlyStage_cv_LASSO.Rdata")
# data <- read.csv("../data/EarlyStageMut.csv",row.names = 1)
# library(OncoCast)
# clin <- read.csv("../data/ClinData.csv",header = T)
# status <- clin$Post.op.Recur.
# time <- clin$Time.to.First.Post.op.Recur
# time[is.na(time)] <- clin$Follow.up..mo...from.DOS.[is.na(time)]
# surv <- as.data.frame(cbind(time,status))
# rownames(surv) <- clin$IMPACT.Sample.ID
# results <- getResults_OC(LASSO,data,numGroups = 2,cuts = 0.66,geneList = NULL,mut.data = T)

# rm(list=ls())
# setwd("~/RonglaiAndy/EarlyStageNSCLC/data/")
# data <- read.csv("MutClin.csv",row.names = 1)
# data <- data[,which(apply(data,2,sum)>4)]
#
#
# library(OncoCast)
# temp <- OncoCast(data,formula = Surv(time,status)~.,method = c("LASSO"),
#          runs = 25,cores = 8,
#          nonPenCol = c("SUV","ApproachOpen","HistologySolid",
#                        "HistologyMicro","HistologyAcinar","HistologyLepidic",
#                        "HistologyPapillary","StageII","StageIII","VPI","LVI"),
#          pathResults = "../results/",
#          studyType = "EarlyStage_WithClin",save=F)
#
# temp$LASSO[[2]]
# lasso.results.clin <- getResults_OC(temp$ENET,data,numGroups = 2,cuts=0.5,mut.data = T)
# lasso.results.clin$ciSummary
# lasso.results.clin$selectInflPlot
# lasso.results.clin$RiskHistogram
# lasso.results.clin$SurvSum
# lasso.results.clin$mut_Plot



# library(OncoCast)
# temp <- OncoCast(data,formula = Surv(time,status)~.,method = c("LASSO"),
#          runs = 10,cores = 8,
#          nonPenCol = c("SUV","ApproachOpen","HistologySolid",
#                        "HistologyMicro","HistologyAcinar","HistologyLepidic"),
#                       # "HistologyPapillary","StageII","StageIII","VPI","LVI"),
#          pathResults = "../results/",
#          studyType = "EarlyStage_WithClinNoPen",save=F)
# temp[[1]][[2]]


# library(OncoCast)
# Out <- OncoCast(data=survData,formula = Surv(time,status)~.,sampling="cv",
#                 nonPenCol = NULL,
#                 cores=2,runs=25,method=c("LASSO"),save=F)
# lasso.results <- getResults_OC(Out$LASSO,data=survData,numGroups=4,cuts = c(0.25,0.5,0.75),mut.data = T)
#
# lasso.results$MutProfiles
# revRowInd <- match(c(1:length(lasso.results$MutProfiles$rowInd)), lasso.results$MutProfiles$rowInd)
# revColInd <- match(c(1:length(lasso.results$MutProfiles$colInd)), lasso.results$MutProfiles$colInd)
# cols <- colorpanel(nrow(lasso.results$MutProfiles$carpet), low="green", high="red")
#
# heatmap.2(t(lasso.results$MutProfiles$carpet)[revRowInd, revColInd],
#           dendrogram="none",  Rowv=NA, Colv=NA,
#           trace="none", labCol = "",
#           ColSideColors=cols,
#           key=FALSE, margins = c(0,7),
#           col=colorpanel(2, low="white", high="black"),
#           lwid=c(0.1,4), lhei=c(0.1,4))


#out <- outputSummary(Out$LASSO)
#out <- outputSummary(Out$ENET)
# out <- outputSummary(Out$ENET)
# riskout <- riskStrat(survData,out$average.risk,numGroups = 2,cuts=0.5)
#
# data <- riskout$data.out
# topHits <- out$topHits
# mut.results <- mutSummary(data,topHits,numGroups = 2,geneList=NULL)
#
# in.data <- as.data.frame(matrix(rbinom(5*20,1,0.5),nrow=20,ncol = 5))
# colnames(in.data) <- c("ImpCov1","ImpCov2","ImpCov3","ImpCov4","Cov7")
# rownames(in.data) <- paste0("Incoming",1:20)
# Incoming <- predictIncoming(Out$LASSO,in.data,surv.print = c(5,10,15),riskRefit = out$RiskRefit)
#

