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
       ,lubridate
       ,rstan # for save/readRDS error?
       ,feather
)


# CRS
wgs_84 <- "+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs "

# Sacramento, CA, UTM 10S, meters
epsg_26911 <- "+proj=utm +zone=10 +ellps=GRS80 +datum=NAD83 +units=m +no_defs"

# Oregon North NAD83 HARN meters
epsg_2838 <- "+proj=lcc +lat_1=46 +lat_2=44.33333333333334 +lat_0=43.66666666666666 +lon_0=-120.5 +x_0=2500000 +y_0=0 +ellps=GRS80 +units=m +no_defs "

# calling our purpleair json webscrape function to generate a list of ALL sensors
#python.load("./purpleair_id_key.py", get.exception = TRUE) # this unexpectedly crashes when running python within RStudio
# run from bash instead...

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


# Sensor A testing
#row <- pa_sf[1,]

# Sensor B testing
#row <- pa_sf[2,]

# create function to collect purpleair data 8000 rows at a time
thingspeak_collect <- function(row, start="2016-05-15", end="2018-05-15") {
  
  # for testing
  #start_date <- "2018-05-07"
  #end_date <- "2018-05-14"
  
  # file path
  output_path <- paste0("./data/output/", format(Sys.time(), "%Y-%m-%d"), "-thingspeak.txt")
  #con <- file(output_path)
  
  
  # primary api id and key pairs
  primary_id <- row$THINGSPEAK_PRIMARY_ID
  primary_key <- row$THINGSPEAK_PRIMARY_ID_READ_KEY
  
  # secondary api id and key pairs
  secondary_id <- row$THINGSPEAK_SECONDARY_ID
  secondary_key <- row$THINGSPEAK_SECONDARY_ID_READ_KEY
  
  
  # need to break up our entire request into 8000 length chunks...
  weeks <- seq(from = as.Date(start)
               ,to = as.Date(end)
               ,by = "week") %>% as.data.frame()
  
  # assign vector name
  colnames(weeks) <- "date"

  # tidy attributes for our output dataframe
  output_names <- c("created_at"
                    ,"entry_id"
                    ,"field"
                    ,"value")  
  
  # create empty dataframe to store all of our api request results
  output_df <- data.frame(matrix(ncol = length(output_names)
                                 ,nrow = 0))
    
  
  # make weekly request to api (need to vectorize this soooo bad....)
  for (i in 1:nrow(weeks)) {
    
    # extract start and end dates from our weekly sequence
    start_date <- weeks$date[i]
    end_date <- weeks$date[i+1]
    
    # primary url to pull from api
    primary_url <- paste0("https://api.thingspeak.com/channels/"
                          ,primary_id
                          ,"/feeds.json?api_key="
                          ,primary_key
                          ,"&start="
                          ,start_date
                          ,"%2000:00:00&end="
                          ,end_date
                          ,"%2000:00:00")
    
    # secondary url to pull from api
    secondary_url <- paste0("https://api.thingspeak.com/channels/"
                            ,secondary_id
                            ,"/feeds.json?api_key="
                            ,secondary_key
                            ,"&start="
                            ,start_date
                            ,"%2000:00:00&end="
                            ,end_date
                            ,"%2000:00:00")
    
    
    # request api with exception handling
    try(primary_request <- fromJSON(primary_url))
    try(secondary_request <- fromJSON(secondary_url))
    
    # break if request is NULL
    if (is_empty(primary_request$feeds) | is_empty(secondary_request$feeds)) {
      print(paste0(start_date, "-", end_date, " ", row$Label, " is empty..."))
      #break
      
    } else {
      
      
      # channel A field names
      primary_fields_a <- c("created_at"
                            ,"entry_id"
                            ,"pm1_0_atm"
                            ,"pm2_5_atm"
                            ,"pm10_0_atm"
                            ,"uptime_min"
                            ,"rssi_wifi_strength"
                            ,"temp_f"
                            ,"humidity"
                            ,"pm2_5_cf_1")
      
      secondary_fields_a <- c("created_at"
                              ,"entry_id"
                              ,"p_0_3_um"
                              ,"p_0_5_um"
                              ,"p_1_0_um"
                              ,"p_2_5_um"
                              ,"p_5_0_um"
                              ,"p_10_0_um"
                              ,"p1_0_cf_1"
                              ,"p10_0_cf_1")
      
      #channel B field names
      primary_fields_b <- c("created_at"
                            ,"entry_id"
                            ,"pm1_0_atm"
                            ,"pm2_5_atm"
                            ,"pm10_0_atm"
                            ,"free_heap_memory"
                            ,"analog_input"
                            ,"sensor_firmware_pressure"
                            ,"not_used"
                            ,"pm2_5_cf_1")
      
      secondary_fields_b <- c("created_at"
                              ,"entry_id"
                              ,"p_0_3_um"
                              ,"p_0_5_um"
                              ,"p_1_0_um"
                              ,"p_2_5_um"
                              ,"p_5_0_um"
                              ,"p_10_0_um"
                              ,"pm1_0_cf_1"
                              ,"pm10_0_cf_1")
      
      # A and B sensors provide different fields!
      if (is.na(row$ParentID)) {
        
        # assign A field names
        primary_df <- primary_request$feeds
        colnames(primary_df) <- primary_fields_a
        
        secondary_df <- secondary_request$feeds
        colnames(secondary_df) <- secondary_fields_a
        
        
      } else {
        
        # assign B field names
        primary_df <- primary_request$feeds
        colnames(primary_df) <-primary_fields_b
        
        secondary_df <- secondary_request$feeds
        colnames(secondary_df) <- secondary_fields_b
        
      }
      
      # attach PurpleAir API attributes to thingspeak data
      primary_df$Label <- row$Label
      primary_df$ID <- row$ID
      primary_df$DEVICE_LOCATIONTYPE <- row$DEVICE_LOCATIONTYPE
      primary_df$geometry <- row$geometry
      
      secondary_df$Label <- row$Label
      secondary_df$ID <- row$ID
      secondary_df$DEVICE_LOCATIONTYPE <- row$DEVICE_LOCATIONTYPE
      secondary_df$geometry <- row$geometry
      
      # these are different depending on which request is being made (primary/secondary)
      #primary_df$THINGSPEAK_PRIMARY_ID
      
      # filter out indoor purpleair data
      primary_df <- primary_df %>% filter(DEVICE_LOCATIONTYPE == "outside")
      primary_df <- primary_df %>% dplyr::select(-DEVICE_LOCATIONTYPE) # threw error without dplyr::
      
      secondary_df <- secondary_df %>% filter(DEVICE_LOCATIONTYPE == "outside")
      secondary_df <- secondary_df %>% dplyr::select(-DEVICE_LOCATIONTYPE) # thre error without dplyr::
      
      # convert to tidy data
      primary_df <- primary_df %>% gather(field, value, -c(created_at, entry_id, Label, ID, geometry))
      secondary_df <- secondary_df %>% gather(field, value, -c(created_at, entry_id, Label, ID, geometry))
      
      # combine primary and secondary data into single tidy df
      tidy_df <- rbind(primary_df, secondary_df)
      
      
      # join is inefficient!
      #df <- full_join(primary_df, secondary_df)
    
      # convert to tidy dataframe (needed for bind_rows when making weekly requests)
      #tidy_df <- df %>% gather(field, value, -c(created_at, entry_id))
      
      # bind single week to total requests
      output_df <- rbind(tidy_df, output_df) # takes up too much RAM in the long run...
      #output_df <- rbind(tidy_df) # work with legacy code below
      
    }
      
      
    }
    
  # testing this out real quick...
  #saveRDS(output_df, output_path)
  #return(output_df)
  
  if(!exists(output_path)) {
    
    write.table(output_df
                ,output_path
                ,row.names = FALSE
                ,col.names = TRUE)
    
  } else {
    
    write.table(output_df
                ,output_path
                ,row.names = FALSE
                ,append = TRUE)
    
  }


}


# for testing purposes
test <- pa_sf[1,]

# apply our read function across each row of our pa_sf df
df <- ddply(pa_sf
      ,MARGIN = 1 # applies over rows
      ,FUN = thingspeak_collect
      )


write_feather(as.data.frame(df), "./output/2018-05-16-output.feather")
saveRDS(df, "./output/2018-05-16-output.RDS")
write.csv(df, "./output/2018-05-16-output.csv")
