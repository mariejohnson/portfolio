closeAllConnections() # closes all file connections (like PDFs, PNGs, CSVs)
rm(list = ls()) # Clear variables
cat("\014") # Clear console

# Objective ---------------------------------------------------------------
# In this code we will explore summer land surface 
# temperatures (LST) at the University of Montana (UMT) using ECOSTRESS
# LST data. We'll find the best places to stay cool in the summer on campus!

# Libraries ---------------------------------------------------------------
setwd('/home/marie/portfolio/UM') # Set this to your working directory
library(raster)
library(tidyverse)
library(lubridate)

# Import LST files
summerList <- list.files(path='/home/marie/portfolio/UM/LST/summer', full.names = T) # Raw LST file list
umShp <- shapefile('umt.shp')
# Create template raster to format LST files
tRes <- c(0.0006288207, 0.0006288207) # 70m resolution IS this 70? 0.0006288207
prj4326 <- '+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0'
rstExt <- bbox(umShp)
r2 <- extent(rstExt)
rstTmp <- raster(crs=prj4326, ext=r2, resolution = tRes)

mskStack <- function(rastFiles, tmpRst, msk){ # rastFiles: creates from list.files, 
  require(raster)
  rastSt <- stack()
  for(i in 1:length(rastFiles)) {
    rastOut <- raster(rastFiles[i]) # read in raster from list
    prjR <- projectRaster(rastOut, tmpRst)
    rastMsk <- mask(prjR, msk)
    rastSt <- stack(rastSt, rastMsk)
  }
  rastSt
}

sLST <- mskStack(summerList, rstTmp, umShp)
library(RColorBrewer)
orPal <- brewer.pal(n = 9, name = "OrRd")
# Let's inspect the images for any obvious anomolies 
plot(fLST, col = orPal) # Some of the rasters like the 2nd, 3rd and 13th look heavily modeled or there may clouds present
# We'll keep that in mind as we continue our analysis.

# These temperature are in K and the scale factor is 0.02 
kLST <- sLST * 0.02
# Since most of us don't think in terms of Kelvin, we'll change to Fahrenheit
fLST <- ((kLST - 273.15) * 9/5) + 32
# Let's take another look
plot(fLST, col = orPal)

# Clearly, image 2 does not make sense. We don't see below zero temperatures in July
# in Montana. Image 3 doesn't make sense either. Image 13 is also pretty suspect
# as well. So we'll remove those images.
fLST <- dropLayer(fLST,c(2,3,13))
plot(fLST, col = orPal)
mnT <- mean(fLST)
library(leaflet)

m <- leaflet() %>%
  addTiles() %>%  # Add default OpenStreetMap map tiles
  addMarkers(lng=-113.9828, lat=46.8619)
m  # Print the map

pal <- colorNumeric(orPal, values(mnT),
                    na.color = "transparent")

leaflet() %>% addTiles() %>%
  addRasterImage(mnT, colors = pal, opacity = 0.9) %>%
  addLegend(pal = pal, values = values(mnT),
            title = "July Surface Temp (F)")
