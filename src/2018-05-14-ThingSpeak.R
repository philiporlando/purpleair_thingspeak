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

# Oregon North NAD83 Meters UTM Zone 10
epsg_26910 <- "+proj=utm +zone=10 +ellps=GRS80 +datum=NAD83 +units=m +no_defs "

# calling our purpleair json webscrape function to generate a list of ALL sensors
#python.load("./purpleair_id_key.py", get.exception = TRUE) # this unexpectedly crashes when running python within RStudio
# it runs from Rstudio's terminal on linux
# runing directly from bash is the fastest...

# reading in shapefiles for the entire US
urban_areas <- readOGR(dsn = "./data/tigerline/tl_2017_us_uac10.shp")

# filtering out only Portland, OR shapefiles
pdx <- subset(urban_areas, str_detect(NAME10, "Portland, OR"))
pdx <- spTransform(pdx, CRSobj = CRS(epsg_26910))
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



## connecting to local db
host <- 'http://pgsql120.rc.pdx.edu'
db <- 'canopycontinuum'
user <- 'porlando'
port <- 5433
pw <- scan("./batteries.pgpss", what = "")



# deletes existing db table observation is choice == "yes"
choice <- readline('DELETE TABLE observation?! (y/n)')

if (tolower(choice) == "y" | tolower(choice) == "yes") {
  
  # initally connect to clear existing data
  con <- dbConnect(drv = RPostgres::Postgres()
                   ,dbname = db
                   ,host = host
                   ,port = port
                   ,password = pw
                   ,user = user)
  
  # deletes ALL rows from observation table:
  #txt <- "delete from observation;"
  delete_table <- "delete from observation;"
  vacuum_table <- "vacuum full observation;"
  
  dbGetQuery(conn = con, delete_table)
  print("Dropping table observation...")
  dbGetQuery(conn = con, vacuum_table)
  print("Vacuum full observation...")
  # closes connection
  dbDisconnect(con)
  
}


# Sensor A testing
#row <- pa_sf[1,]

# Sensor B testing
#row <- pa_sf[2,]


# create function to collect purpleair data 8000 rows at a time
thingspeak_collect <- function(row, start="2016-01-01", end="2018-05-29") {
  
  # for testing
  #start_date <- "2018-05-07"
  #end_date <- "2018-05-14"
  
  # 2-min resolution required for overlapping A & B sensors...
  time_resolution <- "2 min"
  
  # output file paths
  #txt_path <- paste0("./data/output/", format(Sys.time(), "%Y-%m-%d"), "-thingspeak.txt")
  #RDS_path <- paste0("./data/output/", format(Sys.time(), "%Y-%m-%d"), "-thingspeak.RDS")
  #feather_path <- paste0("./data/output/", format(Sys.time(), "%Y-%m-%d"), "-thingspeak.feather")
  
  # for saveRDS, not for dbConnect()
  #con <- file(output_path)
  
  
  # primary api id and key pairs
  primary_id <- row$THINGSPEAK_PRIMARY_ID
  primary_key <- row$THINGSPEAK_PRIMARY_ID_READ_KEY
  
  # secondary api id and key pairs
  secondary_id <- row$THINGSPEAK_SECONDARY_ID
  secondary_key <- row$THINGSPEAK_SECONDARY_ID_READ_KEY
  
  # convert geometry to text for data wrangling
  row$geometry <- st_as_text(row$geometry
                             ,EWKT = TRUE)
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
                    ,"label"
                    ,"id"
                    ,"geom"
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
    # include http status code handling in future!
    # avoid http 503 error from thingspeak
    
    # for (i in 1:100) {
    #   
    #   primary_result <- GET(primary_url)
    #   print(primary_result$status_code)
    # 
    #   
    # }
    
  
    # try pulling from thinspeak API  
    try(primary_request <- jsonlite::fromJSON(primary_url))
    try(secondary_request <- jsonlite::fromJSON(secondary_url))
    
    # next if request is NULL
    if (is_empty(primary_request$feeds) | is_empty(secondary_request$feeds)) {
      print(paste0(start_date, "-", end_date, " ", row$Label, " is empty..."))
      next
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
                              ,"pm1_0_cf_1"
                              ,"pm10_0_cf_1")
      
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
        
        # read in primary data for A sensor
        primary_df <- primary_request$feeds
        
        # assign A field names for primary data
        colnames(primary_df) <- primary_fields_a
        
        # remove non-numeric columns before grouping by date
        primary_df <- primary_df %>% dplyr::select(-c(entry_id, uptime_min, rssi_wifi_strength))

        # cast from character to numeric class
        primary_df$pm1_0_atm <- as.numeric(primary_df$pm1_0_atm)
        primary_df$pm2_5_atm <- as.numeric(primary_df$pm2_5_atm)
        primary_df$pm10_0_atm <- as.numeric(primary_df$pm10_0_atm)
        primary_df$temp_f <- as.numeric(primary_df$temp_f)
        primary_df$humidity <- as.numeric(primary_df$humidity)
        primary_df$pm2_5_cf_1 <- as.numeric(primary_df$pm2_5_cf_1)
        
        # group by 1-minute to allow overlap between primary and secondary timestamps
        primary_df <- primary_df %>%
          group_by(created_at = cut(as.POSIXct(created_at
                                               ,format = "%Y-%m-%dT%H:%M:%SZ"
                                               ,tz = "GMT"
          )
          ,breaks = time_resolution)) %>%
          summarize_all(funs(mean))
        
        primary_df$created_at <- as.character(primary_df$created_at)
        
        # add sensor label
        primary_df$sensor <- "A"
        
        # read in secondary data for A sensor
        secondary_df <- secondary_request$feeds
        
        # assign A field names for secondary data
        colnames(secondary_df) <- secondary_fields_a
        
        # remove non-numeric columns before grouping
        secondary_df <- secondary_df %>% dplyr::select(-c(entry_id))
        
        # cast from character to numeric class
        secondary_df$p_0_3_um <- as.numeric(secondary_df$p_0_3_um)
        secondary_df$p_0_5_um <- as.numeric(secondary_df$p_0_5_um)
        secondary_df$p_1_0_um <- as.numeric(secondary_df$p_1_0_um)
        secondary_df$p_2_5_um <- as.numeric(secondary_df$p_2_5_um)
        secondary_df$p_5_0_um <- as.numeric(secondary_df$p_0_5_um)
        secondary_df$p_10_0_um <- as.numeric(secondary_df$p_10_0_um)
        secondary_df$pm1_0_cf_1 <- as.numeric(secondary_df$pm1_0_cf_1)
        secondary_df$pm10_0_cf_1 <- as.numeric(secondary_df$pm10_0_cf_1)
        
        # group by 1-minute to allow overlap between primary and secondary timestamps
        secondary_df <- secondary_df %>%
          group_by(created_at = cut(as.POSIXct(created_at
                                               ,format = "%Y-%m-%dT%H:%M:%SZ"
                                               ,tz = "GMT"
          )
          ,breaks = time_resolution)) %>%
          summarize_all(funs(mean))
        
        secondary_df$created_at <- as.character(secondary_df$created_at)
        
        # add sensor label
        secondary_df$sensor <- "A"
        
      } else {
        
        # read in primary data for B sensor
        primary_df <- primary_request$feeds
        
        # assign B field names for primary data
        colnames(primary_df) <-primary_fields_b
        
        
        # remove non-numeric columns before grouping by date
        primary_df <- primary_df %>% dplyr::select(-c(entry_id, free_heap_memory, analog_input, sensor_firmware_pressure, not_used))
        
        # cast from character to numeric
        primary_df$pm1_0_atm <- as.numeric(primary_df$pm1_0_atm)
        primary_df$pm2_5_atm <- as.numeric(primary_df$pm2_5_atm)
        primary_df$pm10_0_atm <- as.numeric(primary_df$pm10_0_atm)
        primary_df$pm2_5_cf_1 <- as.numeric(primary_df$pm2_5_cf_1)
        
        # group by 1-minute to allow overlap between primary and secondary timestamps
        primary_df <- primary_df %>%
          group_by(created_at = cut(as.POSIXct(created_at
                                               ,format = "%Y-%m-%dT%H:%M:%SZ"
                                               ,tz = "GMT"
          )
          ,breaks = time_resolution)) %>%
          summarize_all(funs(mean))
        
        primary_df$created_at <- as.character(primary_df$created_at)
      
        # add sensor label
        primary_df$sensor <- "B"
        
        # read in secondary data for B sensor
        secondary_df <- secondary_request$feeds
        
        # assign B field names for secondary sensor
        colnames(secondary_df) <- secondary_fields_b
        
        # remove non-numeric columns before grouping
        secondary_df <- secondary_df %>% dplyr::select(-c(entry_id))
        
        # cast character to numeric class
        secondary_df$p_0_3_um <- as.numeric(secondary_df$p_0_3_um)
        secondary_df$p_0_5_um <- as.numeric(secondary_df$p_0_5_um)
        secondary_df$p_1_0_um <- as.numeric(secondary_df$p_1_0_um)
        secondary_df$p_2_5_um <- as.numeric(secondary_df$p_2_5_um)
        secondary_df$p_5_0_um <- as.numeric(secondary_df$p_5_0_um)
        secondary_df$p_10_0_um <- as.numeric(secondary_df$p_10_0_um)
        secondary_df$pm1_0_cf_1 <- as.numeric(secondary_df$pm1_0_cf_1)
        secondary_df$pm10_0_cf_1 <- as.numeric(secondary_df$pm10_0_cf_1)
        
        
        # group by 1-minute to allow overlap between primary and secondary timestamps
        secondary_df <- secondary_df %>%
          group_by(created_at = cut(as.POSIXct(created_at
                                               ,format = "%Y-%m-%dT%H:%M:%SZ"
                                               ,tz = "GMT"
          )
          ,breaks = time_resolution)) %>%
          summarize_all(funs(mean))
        
        secondary_df$created_at <- as.character(secondary_df$created_at)
        
        
        # add sensor label
        secondary_df$sensor <- "B"
        
      }
      
      
      if(row$DEVICE_LOCATIONTYPE == "") {
        
        # attach PurpleAir API attributes to primary thingspeak data
        primary_df$label <- row$Label
        primary_df$id <- row$ID
        #primary_df$DEVICE_LOCATIONTYPE <- row$DEVICE_LOCATIONTYPE
        primary_df$geom <- row$geometry
        #print("test point 1")
        
        
        # attach PurpleAir API attributes to secondary thingspeak data
        secondary_df$label <- row$Label
        secondary_df$id <- row$ID
        #secondary_df$DEVICE_LOCATIONTYPE <- row$DEVICE_LOCATIONTYPE
        secondary_df$geom <- row$geometry
        #print("test point 2")
        
      } else {
        
        # attach PurpleAir API attributes to primary thingspeak data
        primary_df$label <- row$Label
        primary_df$id <- row$ID
        primary_df$DEVICE_LOCATIONTYPE <- row$DEVICE_LOCATIONTYPE
        primary_df$geom <- row$geometry
        #print("test point 3")
        
        
        # attach PurpleAir API attributes to secondary thingspeak data
        secondary_df$label <- row$Label
        secondary_df$id <- row$ID
        secondary_df$DEVICE_LOCATIONTYPE <- row$DEVICE_LOCATIONTYPE
        secondary_df$geom <- row$geometry
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
      
      # create wide dataframe to use less rows (tidy 100k rows per week per sensor)
      df_wide <- full_join(primary_df, secondary_df)
      
      # reorder columns 
      df_wide <- df_wide %>% dplyr::select(
        
        created_at # put this first out of convention
        #,entry_id
        ,id
        ,sensor
        ,label
        #,uptime_min # Channel A
        #,rssi_wifi_strength # Channel A
        #,temp_f # Channel A
        #,humidity # Channel A
        ,pm1_0_atm
        ,pm2_5_atm
        ,pm10_0_atm
        ,pm1_0_cf_1
        ,pm2_5_cf_1
        ,pm10_0_cf_1
        ,p_0_3_um
        ,p_0_5_um
        ,p_1_0_um
        ,p_2_5_um
        ,p_5_0_um
        ,p_10_0_um
        ,geom # put this last out of convention
      )

      # necessary for using st_write()
      df_wide$geom <- st_as_sfc(df_wide$geom)
      df_wide <- st_as_sf(df_wide)
      observation <- df_wide
      
      
      # open connection to our db
      con <- dbConnect(drv = RPostgres::Postgres()
                       ,dbname = db
                       ,host = 'pgsql102.rc.pdx.edu' # not sure why object host isn't working...
                       ,port = port
                       ,password = pw
                       ,user = user)
      
      # writes only new observations to db
      # st_write(dsn = con
      #             ,obj = observation # df to write
      #             ,geom_name = "geom"
      #             ,table = 'observation' # relation name
      #             ,query = "INSERT INTO observation ON CONFLICT DO NOTHING;" # this isn't working, writes twice...
      #             ,layer_options = "OVERWRITE=true"
      #             ,drop_table = FALSE
      #             ,try_drop = FALSE
      #             ,debug = TRUE
      #             ,append = TRUE
      # )
      
      
      # write output_df to our db
      invisible(try(dbWriteTable(conn = con
                             ,"observation" # db table name
                             ,df_wide # only append new data (!output_df)
                             ,append = TRUE
                             ,row.names = FALSE)))
      #print("Appending db...")
      # close connection to db
      dbDisconnect(con)
      
      
      # remove NA field "not_used"
      # if("not_used" %in% colnames(primary_df)) {
      #   
      #   primary_df <- primary_df %>% dplyr::select(-not_used)
      #   #print("test point 7")
      # }
      

      # convert to tidy data
      # primary_df <- primary_df %>% gather(field
      #                                     ,value
      #                                     ,-c(created_at
      #                                         ,entry_id
      #                                         ,label
      #                                         ,id
      #                                         ,sensor
      #                                         ,geom
      #                                         )
      #                                     )
      
      #print("test point 8")
      # secondary_df <- secondary_df %>% gather(field
      #                                         ,value
      #                                         ,-c(created_at
      #                                             ,entry_id
      #                                             ,label
      #                                             ,id
      #                                             ,sensor
      #                                             ,geom
      #                                             )
      #                                         )
      #print("test point 9")
      # combine primary and secondary data into single tidy df
      # tidy_df <- rbind(primary_df, secondary_df)
      #tidy_df$geom <- row$geometry # trying to manipulate geom differently
      #print("test point 10")
      
      # join is inefficient!
      #df <- full_join(primary_df, secondary_df)
    
      # convert to tidy dataframe (needed for bind_rows when making weekly requests)
      #tidy_df <- df %>% gather(field, value, -c(created_at, entry_id))
      
      # bind single week to total requests
      #output_df <- rbind(tidy_df, output_df) # not needed with db
      
      # # open connection to our db
      # con <- dbConnect(drv = RPostgres::Postgres()
      #                  ,dbname = db
      #                  ,host = host
      #                  ,port = port
      #                  ,password = pw
      #                  ,user = user)
      # 
      # 
      # # write output_df to our db
      # invisible(dbWriteTable(con
      #              ,"observation"
      #              ,tidy_df # only append new data (!output_df)
      #              ,append = TRUE
      #              ,row.names = FALSE))
      # #print("Appending db...")
      # # close connection to db
      # dbDisconnect(con)
      
      #return(output_df) # only for testing...
      #print("test point 11")
      
      # takes up too much RAM in the long run...
      #output_df <- rbind(tidy_df) # work with legacy code below
      
      
      # testing this out real quick...
      #saveRDS(output_df, output_path)
      #return(output_df)
      
      
      # if(!file.exists(txt_path)) {
      # 
      #   
      #   print(paste0("Creating file: ", basename(txt_path)))
      #   write.table(output_df
      #               ,txt_path
      #               ,row.names = FALSE
      #               ,col.names = TRUE)
      # 
      #   #print("test point 12")
      # 
      # } else {
      # 
      #   print(paste0("Appending file: ", basename(txt_path)))
      #   write.table(output_df
      #               ,txt_path
      #               ,row.names = FALSE
      #               ,append = TRUE # append if already exists
      #               ,col.names = FALSE
      #               ,sep =  ",")
      #   #print("test point 13")
      # 
      # }
      
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
# test <- pa_sf[1,]
# 
# # this will append data that already exists within the files...
# # figure out how to append intelligently... only add distinct values to file/db in future!
# invisible(apply(test
#       ,MARGIN = 1
#       ,FUN = thingspeak_collect
#       ))

## apply our read function across each row of our pa_sf df
invisible(apply(pa_sf
      ,MARGIN = 1 # applies over rows
      ,FUN = thingspeak_collect
      ))

## connecting to local db
# host <- "localhost"
# db <- "purpleair"
# user <- "porlando"
# port <- 5432
# pw <- scan("./batteries.pgpss", what = "")
# 
# con <- dbConnect(drv = RPostgres::Postgres()
#                  ,dbname = db
#                  ,host = host
#                  ,port = port
#                  ,password = pw
#                  ,user = user)
# 
# 
# dbListTables(conn = con)
# 
# dbListFields(conn = con
#              ,name = "observation"
#              )
# 
# dbWriteTable(con
#              ,"observation"
#              ,df
#              ,append = TRUE
#              ,row.names = FALSE)
# 
# # delete ALL data from a given table!
# #txt <- "delete from observation;"
# #dbGetQuery(conn = con, txt)
# dbDisconnect(con)



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
