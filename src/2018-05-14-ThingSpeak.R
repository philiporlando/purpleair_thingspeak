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
       #,rstan # for save/readRDS error?
       ,feather
       ,snow #parallel computing
       #,devtools
       #,rJython
       #,rJava
       #,rjson
)


# for R texting 
# install_github("trinker/gmailR")
# install_github("kbroman/mygmailR")
# library(mygmailR)




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
thingspeak_collect <- function(row, start="2016-01-01", end="2018-05-15") {
  
  # for testing
  #start_date <- "2018-05-07"
  #end_date <- "2018-05-14"
  
  # output file paths
  txt_path <- paste0("./data/output/", format(Sys.time(), "%Y-%m-%d"), "-thingspeak.txt")
  RDS_path <- paste0("./data/output/", format(Sys.time(), "%Y-%m-%d"), "-thingspeak.RDS")
  feather_path <- paste0("./data/output/", format(Sys.time(), "%Y-%m-%d"), "-thingspeak.feather")
  
  #con <- file(output_path)
  
  
  # primary api id and key pairs
  primary_id <- row$THINGSPEAK_PRIMARY_ID
  primary_key <- row$THINGSPEAK_PRIMARY_ID_READ_KEY
  
  # secondary api id and key pairs
  secondary_id <- row$THINGSPEAK_SECONDARY_ID
  secondary_key <- row$THINGSPEAK_SECONDARY_ID_READ_KEY
  
  # convert geometry to text for data wrangling
  row$geometry <- st_as_text(row$geometry)
  #row$geometry <- st_as_sfc(row$geometry) # converts back to geom
  
  # need to break up our entire request into 8000 length chunks...
  weeks <- seq(from = as.Date(start)
               ,to = as.Date(end)
               ,by = "week") %>% as.data.frame()
  
  # assign vector name
  colnames(weeks) <- "date"

  # tidy attributes for our output dataframe
  output_names <- c("created_at"
                    ,"entry_id"
                    ,"sensor"
                    ,"Label"
                    ,"ID"
                    ,"geometry"
                    ,"field"
                    ,"value"
                    #,"geometry"
                    )  
  
  # create empty dataframe to store all of our api request results
  output_df <- data.frame(matrix(ncol = length(output_names)
                                 ,nrow = 0))
    
  
  # make weekly request to api (need to vectorize this soooo bad....)
  for (i in 1:nrow(weeks)) {
    
    # extract start and end dates from our weekly sequence
    start_date <- weeks$date[i]
    end_date <- weeks$date[i+1]
    
    # if the end data is in the future, then use the current date as the final end point
    if (is.na(end_date)) {
      
      end_date <- Sys.Date()
      
    }
    
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
    try(primary_request <- jsonlite::fromJSON(primary_url))
    try(secondary_request <- jsonlite::fromJSON(secondary_url))
    
    # break if request is NULL
    if (is_empty(primary_request$feeds) | is_empty(secondary_request$feeds)) {
      print(paste0(start_date, "-", end_date, " ", row$Label, " is empty..."))
      #break
      
    } else {
      
      print(paste0(start_date, "-", end_date, " ", row$Label, " is being processed..."))
      
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
        primary_df$sensor <- "A"
        
        secondary_df <- secondary_request$feeds
        colnames(secondary_df) <- secondary_fields_a
        secondary_df$sensor <- "A"
        
      } else {
        
        # assign B field names
        primary_df <- primary_request$feeds
        colnames(primary_df) <-primary_fields_b
        primary_df$sensor <- "B"
        
        secondary_df <- secondary_request$feeds
        colnames(secondary_df) <- secondary_fields_b
        secondary_df$sensor <- "B"
        
      }
      
      
      if(row$DEVICE_LOCATIONTYPE == "") {
        
        # attach PurpleAir API attributes to primary thingspeak data
        primary_df$Label <- row$Label
        primary_df$ID <- row$ID
        #primary_df$DEVICE_LOCATIONTYPE <- row$DEVICE_LOCATIONTYPE
        primary_df$geometry <- row$geometry
        #print("test point 1")
        
        
        # attach PurpleAir API attributes to secondary thingspeak data
        secondary_df$Label <- row$Label
        secondary_df$ID <- row$ID
        #secondary_df$DEVICE_LOCATIONTYPE <- row$DEVICE_LOCATIONTYPE
        secondary_df$geometry <- row$geometry
        #print("test point 2")
        
      } else {
        
        # attach PurpleAir API attributes to primary thingspeak data
        primary_df$Label <- row$Label
        primary_df$ID <- row$ID
        primary_df$DEVICE_LOCATIONTYPE <- row$DEVICE_LOCATIONTYPE
        primary_df$geometry <- row$geometry
        #print("test point 3")
        
        
        # attach PurpleAir API attributes to secondary thingspeak data
        secondary_df$Label <- row$Label
        secondary_df$ID <- row$ID
        secondary_df$DEVICE_LOCATIONTYPE <- row$DEVICE_LOCATIONTYPE
        secondary_df$geometry <- row$geometry
        #print("test point 4")
        
        # these are different depending on which request is being made (primary/secondary)
        #primary_df$THINGSPEAK_PRIMARY_ID # not needed...
        
        # filter out indoor purpleair data
        primary_df <- primary_df %>% filter(DEVICE_LOCATIONTYPE == "outside")
        primary_df <- primary_df %>% dplyr::select(-DEVICE_LOCATIONTYPE) # threw error without dplyr::
        #print("test point 5")
        
        secondary_df <- secondary_df %>% filter(DEVICE_LOCATIONTYPE == "outside")
        secondary_df <- secondary_df %>% dplyr::select(-DEVICE_LOCATIONTYPE) # thre error without dplyr::
        #print("test point 6")
        
      }
      

      # remove NA field "not_used"
      if("not_used" %in% colnames(primary_df)) {
        
        primary_df <- primary_df %>% dplyr::select(-not_used)
        #print("test point 7")
      }
      

      # convert to tidy data
      primary_df <- primary_df %>% gather(field
                                          ,value
                                          ,-c(created_at
                                              ,entry_id
                                              ,Label
                                              ,ID
                                              ,sensor
                                              ,geometry
                                              )
                                          )
      #print("test point 8")
      secondary_df <- secondary_df %>% gather(field
                                              ,value
                                              ,-c(created_at
                                                  ,entry_id
                                                  ,Label
                                                  ,ID
                                                  ,sensor
                                                  ,geometry
                                                  )
                                              )
      #print("test point 9")
      # combine primary and secondary data into single tidy df
      tidy_df <- rbind(primary_df, secondary_df)
      #tidy_df$geometry <- row$geometry # trying to manipulate geom differently
      #print("test point 10")
      
      # join is inefficient!
      #df <- full_join(primary_df, secondary_df)
    
      # convert to tidy dataframe (needed for bind_rows when making weekly requests)
      #tidy_df <- df %>% gather(field, value, -c(created_at, entry_id))
      
      # bind single week to total requests
      output_df <- rbind(tidy_df, output_df)
      #print("test point 11")
      
      # takes up too much RAM in the long run...
      #output_df <- rbind(tidy_df) # work with legacy code below
      
      
      # testing this out real quick...
      #saveRDS(output_df, output_path)
      #return(output_df)
      
      
      if(!file.exists(txt_path)) {

        
        print(paste0("Creating file: ", basename(txt_path)))
        write.table(output_df
                    ,txt_path
                    ,row.names = FALSE
                    ,col.names = TRUE)

        #print("test point 12")

      } else {

        print(paste0("Appending file: ", basename(txt_path)))
        write.table(output_df
                    ,txt_path
                    ,row.names = FALSE
                    ,append = TRUE # append if already exists
                    ,col.names = FALSE
                    ,sep = ",")
        #print("test point 13")

      }
      
      # # reading in old_df is too expensive, exceeding 32GB!!!!
      # #  Error in coldataFeather(x, i) : 
      # #     embedded nul in string: '\0\0\0\0\t\0\0\0\022\0\0\0\033\0\0\0$\0\0\0-\0\0\0' 
      
      # # fix to append RDS without writing over...
      # if(!file.exists(RDS_path)) {
      # 
      #   print(paste0("Creating file: ", basename(RDS_path)))
      #   saveRDS(output_df
      #               ,file = RDS_path
      #               ,ascii = FALSE
      #               ,compress = TRUE
      #           )
      # 
      #   # #print("test point 14")
      # 
      # } else {
      # 
      #   print(paste0("Appending file: ", basename(RDS_path)))
      # 
      # 
      #   old_RDS <- readRDS(RDS_path)
      #   new_RDS <- rbind(old_RDS, output_df)
      # 
      #   saveRDS(new_RDS
      #               ,file = RDS_path
      #               ,ascii = FALSE
      #               ,compress = TRUE # append if already exists
      #               )
      # 
      #   # #print("test point 15")
      # 
      # }
      
      
      # # fix to append feather without writing over...
      # if(!file.exists(feather_path)) {
      #   
      #   print(paste0("Creating file: ", basename(feather_path)))
      #   
      #   write_feather(output_df
      #                 ,feather_path
      #   )
      #   
      #   #print("test point 16")
      #   
      # } else {
      #   
      #   print(paste0("Appending file: ", basename(feather_path)))
      #   
      #   old_feather <- read_feather(feather_path)
      #   new_feather <- rbind(old_feather, output_df)
      #   
      #   write_feather(new_feather
      #                 ,feather_path
      #   )
      #   
      #   #print("test point 17")
      #   
      # }
      
      
    }
      
      
    }
  
  # cleaning up  
  invisible(gc())

}

# # for testing purposes
# test <- pa_sf[1:10,]
# 
# # this will append data that already exists within the files...
# # figure out how to append intelligently... only add distinct values to file/db in future!
# invisible(apply(test
#       ,MARGIN = 1
#       ,FUN = thingspeak_collect
#       ))


# apply our read function across each row of our pa_sf df
invisible(apply(pa_sf
      ,MARGIN = 1 # applies over rows
      ,FUN = thingspeak_collect
      ))

# broken on linux... error in jython.exec(rJython, mail) : (-1, 'SSL exception')
# send_text("sent from R", "Your R process is done.")
# send_gmail("sent from R", "Your R process is done.")

## room for parallelization!

# declare cluster object
# clus <- makeCluster(8)
# 
# clusterExport(clus, "thingspeak_collect")
# 
# parRapply(clus
#           ,test
#           ,function(x) thingspeak_collect(x[1]
#                                           ,x[2]
#                                           ,x[3]
#                                           ,x[4]
#                                           ,x[5]
#                                           ,x[6]
#                                           ,x[7]
#                                           ,x[8])
#           )
