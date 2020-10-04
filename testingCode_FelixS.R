for(p in c("caret","devtools","xts", "dimRed", "foreach","tidyr","fastICA"))
  if (!require(p,character.only=TRUE)) {
    install.packages(p)
    require(p,character.only=TRUE)
  }

if (!require("influxdbr2",character.only=TRUE)) {
  devtools::install_github("mvadu/influxdbr2")
  require("influxdbr2",character.only=TRUE)
}