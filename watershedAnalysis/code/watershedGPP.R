closeAllConnections() # closes all file connections (like PDFs, PNGs, CSVs)
rm(list = ls()) # Clear variables
cat("\014") # Clear console


# Description -------------------------------------------------------------



# Objective ---------------------------------------------------------------
# Get MOD17 30m GPP for watershed analysis
# Data source: https://developers.google.com/earth-engine/datasets/catalog/UMT_NTSG_v2_LANDSAT_GPP


# Prerequisites ------------------------------------------------------------
# Google Earth Engine (GEE) account
# RGEE - R's API for RGEE

# Libraries ---------------------------------------------------------------
setwd('/home/marie/portfolio/watershedAnalysis/')
library(reticulate) # Only needed if importing earth engine data with RGEE
library(rgee) # Only needed if importing earth engine data with RGEE
library(cptcity) # Only needed if importing earth engine data with RGEE
library(raster)
library(stars) # Only needed if importing earth engine data with RGEE
library(sf)
library(tidyverse)

# Extract GPP time series rasters  -------------------------------------------------
# Initialize GEE
use_condaenv("gee-base", conda = "auto",required = TRUE)
ee = import("ee")
ee_Initialize(email = 'marie.johnson22@gmail.com', drive = TRUE)


# Extract selected watersheds in northwestern Montana ---------------------
watshs = ee$FeatureCollection('projects/ee-mariejohnson/assets/joeWatersheds')
region1 = watshs$geometry();

gpp = ee$ImageCollection('UMT/NTSG/v2/LANDSAT/GPP')$ # 30m 16-day Landsat Gross Primary Production
filter(ee$Filter$date('2020-01-01', '2021-12-31'))$
select('GPP')$ 
toBands();

# Watershed GPP within the extent of region1. This may take a few minutes.
watshGPP <- ee_as_raster( # saves raster locally to work within R and saves to gdrive and saves in your working directory
  image = gpp,
  dsn = "watershedGPP_2020-2021",
  scale = 30, # 30m 
  region = region1, # Selects extent
  via = "drive",
  add_metadata = TRUE,
  container = "earthEngine") # Folder to store GEE data

# Import local watershed shapefile to mask and crop each watershed.
watersheds <- shapefile('data/watersheds.shp')
# Get GPP for each watershed. This will also reduce the amount of data stored locally
# instead of writing the full extent of the watershed. Each raster stack will be stored
# a list
wsGPP <- lapply(1:nrow(watersheds), function(x) 
  raster::mask(crop(watshGPP, extent(watersheds[x,])), watersheds[x,]))

# Let's visualize the first watershed to make sure everything worked
plot(wsGPP[[1]]) # Looks good!

# Exporting data ----------------------------------------------------------
# If you would like, you can save the list as an R object
library(readr)
write_rds(wsGPP, 'data/gpp/gppByWatershed_2020-2021.rds')
wsGPP <- read_rds('data/gpp/gppByWatershed_2020-2021.rds')

# If you would like a local copy you can write each multilayer raster for each watershed
# First let's create a vector of watershed names (named after a lake that lies within the 
# watershed) and remove the spaces. These will be saved in your working directory.
watN <- gsub(" ", "_", watersheds$LakeName) # Remove spaces in lake names
for (i in 1:length(wsGPP)) {
  a <- wsGPP[[i]]
  writeRaster(a, watN[[i]], format='GTiff')
}

# Transform data ----------------------------------------------------------
# Next, let's transform the data into a data frame so we can visualize the
# time series data
# Create list of data frames
wsg <- lapply(wsGPP, function(x)
  as.data.frame(x, na.rm=T))
# Save the list as an R object if you prefer
write_rds(wsg, 'data/gpp/timeseries_gppByWatershed_2020-2021.rds')

# Write each data frame to a csv with the corresponding watershed lake name
for (i in 1:length(wsg)) {
  a <- wsg[[i]]
  write.csv(a, file=paste('data/timeseries/', watN[[i]], '.csv'), row.names = F)
}

# Here we will grab dates from the layer names and merge data frames for analysis
bigDF <- data.frame() # create and empty data frame, aptly named as it will be quite large!
# This data frame will be in a long format versus the traditional wide format. This makes
# it much easier to work with the data in ggplot. If you'd like the data to be in a wide
# format check out the function pivot_wider()
for (i in 1:length(wsg)) {
  a <- wsg[[i]]
  df <- a %>% 
    mutate(lakeName = watN[[i]]) %>% 
    pivot_longer(cols = 1:46, names_to = 'date') %>% 
    mutate(date = gsub("X","", date)) %>% 
    mutate(date = gsub("_GPP","", date))
  bigDF <- rbind(bigDF,df)
}

# We're going to use the R library lubridate because it's pretty slick for date 
# formatting! And ggplot requires specific date formatting
library(lubridate)
bigDF$date <- as.POSIXct(bigDF$date, format="%Y%j") # year and julian day
bigDF$month <- month(bigDF$date) # add month column
bigDF$year <- year(bigDF$date) # add year column
bigDF$scaleGPP <- (bigDF$value)/10 # scale GPP so that it is gCm^2

# Average monthly GPP for each year and lake
avgGPP <- bigDF %>% 
  group_by(month, year, lakeName) %>% 
  transmute(avgMonthGPP = mean(scaleGPP)) %>% 
  unique()
write.csv(avgGPP, 'data/avg_monthly_GPP_by_watershed.csv', row.names = F)


# Figures -----------------------------------------------------------------
# This is a color blind friendly palette, in this case we'll only be using the first two colors
# listed since there are only two years. If you want a different color just copy the hex code into 
# into one of the first two slots. Check out this site for more color blind friendly palettes
# http://www.cookbook-r.com/Graphs/Colors_(ggplot2)/
cbPalette <- c("#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00")
# If you would like to create one figure at a time simply change it to the
# lake name of interest
avgGPP %>%
  filter(lakeName == c("Black_Lake")) %>%
  ggplot(aes(x=month, y=avgMonthGPP, colour=as.factor(year))) +
  ggtitle("Black Lake GPP ") +
  geom_line(size=1) + 
  # geom_smooth(method="loess", size=1.5, se=FALSE)+ # Uncomment this for a loess fit
  geom_point(size=2.5)+
  scale_colour_manual(values = cbPalette, name="Year")+
  theme_light()+
  labs(y="GPP" ~gCm^2, x="Month")+ # superscript
  theme(axis.title = element_text(size = 26),
        axis.text = element_text(size=22),
        plot.title = element_text(color = "black", size = 25, face = "bold", hjust = 0.5),
        legend.text = element_text(size = 24),
        legend.title = element_text(size = 24))+
  scale_x_continuous(breaks = seq(1, 12, by= 1))

# Create and export all watershed figures at one time
lakesList <- unique(avgGPP$lakeName) # each unique lake name
lake_plots <- list() # Create empty list to store figures
for (lake_ in lakesList) {
  lake_plots[[lake_]] = ggplot(avgGPP %>% filter(lakeName==lake_), aes(x=month, y=avgMonthGPP, colour=as.factor(year))) +
    # geom_smooth(method="loess", size=1.5, se=FALSE)+
    geom_line(size=1)+
    geom_point(size=2.5)+
    scale_colour_manual(values = cbPalette, name="Year")+
    theme_light()+
    ggtitle(lake_) +
    labs(y="GPP" ~gCm^2, x="Month")+ # superscript
    theme(axis.title = element_text(size = 26),
          axis.text = element_text(size=22),
          plot.title = element_text(color = "black", size = 25, face = "bold", hjust = 0.5),
          legend.text = element_text(size = 24),
          legend.title = element_text(size = 24))+
    scale_x_continuous(breaks = seq(1, 12, by= 1))
  print(lake_plots[[lake_]])
  ggsave(lake_plots[[lake_]], file=paste0("plot_", lake_,".png"), width = 44.45, height = 27.78, units = "cm", dpi=300)
  
}


# I'll add a seasonal section here later ----------------------------------


