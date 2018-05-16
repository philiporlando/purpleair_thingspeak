# created by Philip Orlando
# Sustainable Atmospheres Research Lab
# 2018-05-15
# automating data collection from Thingspeak

# load the necessary packages
if (!require(pacman)) {
  install.packages("pacman")
  library(pacman)
}

p_load(readr
       #,ggplot2
       ,plyr
       ,dplyr
       ,tidyr
       ,stringr
       ,magrittr
       ,rgeos
       ,rgdal
       ,sp
       ,leaflet
       ,sf
       ,raster
       ,mapview
       ,tidycensus
       ,tidyverse
       ,RPostgres
       ,RColorBrewer
       ,classInt
       ,htmltools
       ,scales
       ,htmlwidgets
       ,rPython
       ,devtools
       ,httr
       ,jsonlite
)


# geography projection
wgs_84 <- "+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs "

# Sacramento, CA, UTM 10S, meters
epsg_26911 <- "+proj=utm +zone=10 +ellps=GRS80 +datum=NAD83 +units=m +no_defs"

# Oregon North NAD83 HARN meters
epsg_2838 <- "+proj=lcc +lat_1=46 +lat_2=44.33333333333334 +lat_0=43.66666666666666 +lon_0=-120.5 +x_0=2500000 +y_0=0 +ellps=GRS80 +units=m +no_defs "

# calling our purpleair json webscrape function to generate a list of ALL sensors
python.load("./purpleair_id_key.py") # previous version was changing wd to subdir...!

# reading in shapefiles for the entire US
urban_areas <- readOGR(dsn = "./data/tigerline/tl_2017_us_uac10.shp")

# filtering out only Portland, OR shapefiles
pdx <- subset(urban_areas, str_detect(NAME10, "Portland, OR"))
pdx <- spTransform(pdx, CRSobj = CRS(epsg_2838))
pdx <- st_as_sf(pdx)

# reading our scraped data in
pa <- read.csv("./data/pa_id_key/pa_id_key.txt"
               ,stringsAsFactors = FALSE
               ,header = TRUE)

# converting to simple features class
pa_sf <- st_as_sf(pa
                  ,coords = c("Lon", "Lat")
                  ,crs = wgs_84
                  ,na.fail = FALSE)

# transforming to NAD83 Oregon North to match our urban area data...
pa_sf <- st_transform(pa_sf, crs = st_crs(pdx))

# subsetting purpleair sensors that are contained within our urban area
pa_sf <- pa_sf[pdx, ]







# star lab cully
url <- "https://api.thingspeak.com/channels/341967/feeds.json?api_key=KDMDB47BY5X1PW1A&start=2016-01-01%2000:00:00&end=2019-01-01%2000:00:00"
r <- GET(url)
r$status_code
asdf <- fromJSON(url)


# getting ready to iterate
# these variables will be vectors eventually...
id <- "341967"
key <- "KDMDB47BY5X1PW1A"
start_date <- "2016-01-01"
end_date <- "2018-05-15"
url <- paste0("https://api.thingspeak.com/channels/"
              ,id
              ,"/feeds.json?api_key="
              ,key
              ,"&start="
              ,start_date
              ,"%2000:00:00&end="
              ,end_date,
              "%2000:00:00")
r <- GET(url)
r$status_code
asdf <- fromJSON(url)
head(asdf$feeds)
