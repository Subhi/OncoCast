% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/outputSummary.R
\name{outputSummary}
\alias{outputSummary}
\title{outputSummary}
\usage{
outputSummary(OC_object, data)
}
\arguments{
\item{OC_object}{A list object outputed by the VariableSelection function.}

\item{data}{A dataframe that corresponds to the data used to generate the OncoCast output.}
}
\value{
ciSummary Summary of the distribution of the concordance index accross all runs.

inflPlot Bar plot of frequency of the 20 most selected features.

topHits Character vector of the top 10 most selected features.

average.risk Average predicted risk score for each patient in the data set.

data.out The data that was used for the analysis.

selectInflPlot Volcano plot of the selection frequency against the average mean coefficient of each feature accross all runs.
Note that this plot is interactive.

RiskRefit Refitted cox proportional hazard model with the predicted average risk score as the continuous covariate.

RiskHistogram Histogram of the density distribution of the average predicted risk score. Note it has been rescaled from 0 to 10
for simplicity.

Fits Data frame reporting the coefficients found for each feature at each run.

time.type Time unit used. Options are Days or Months.

RiskScoreSummary Distribution summary of the average predicted risk score.
}
\description{
This functions let's the user study the basic output of the OncoCast function. This function takes as input
one of the (or the one) objects returned from the different machine learning algorithms chosen previously.
Only one such object can be inputted everytime in the outputSummary function.
}
\examples{
library(OncoCast)
test <- OncoCast(data=survData,formula=Surv(time,status)~.,
                          method=c("LASSO"),
                          runs = 25,cores = 1,sampling = "cv",
                          pathResults = "./Test/",studyType = "ExampleRun",save=F)
out <- outputSummary(test$LASSO)
}
\keyword{Results}
