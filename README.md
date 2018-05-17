# purpleair_thingspeak

## An alternative to manually downloading historical PurpleAir data!

Here's [PurpleAir's manual download page](purpleair.com/sensorlist). It's great for grabbing historical data for a couple of sensors by hand. However, it quickly becomes a burden to use when attempting to download years worth of data for hundreds of sensors at a time! Cue R and Python to the rescue!

### Overview

In order to automate historical PurpleAir data, I've relied on both the PurpleAir and Thingspeak APIs.

* The `purpleair_id_key.py` script pulls data from the [PurpleAir API](purpleair.com/json) for ALL of the existing PurpleAir sensors in the world and writes it to a file.
* The `2018-05-14-ThingSpeak.R` script then imports this data, and performs a spatial intersection with our target study area. In this case, I'm subsetting only the PurpleAir sensors located within Portland, OR.

However, retrieving historical data is a little more complicated than pulling from the [PurpleAir API](purpleair.com/json). Only the most recent observation is provided by the PurpleAir API.
PurpleAir relies on a [Thingspeak API](https://thingspeak.com/) to store all of their historical data. We can request from this API directly, but we are limited to 8000 observations per request.
Since PurpleAir sensors upload data every 120 seconds, this equates to a maximum of about a week's worth of data per request. This is simply not good enough for the months-years worth of data that I'm looking for! 
My R function `thingspeak_collect()` retrieves ALL of the historical data for each sensor in Portland, OR based on a user defined start and end date. 
I relied on the [split-apply-combine](https://www.jstatsoft.org/article/view/v040i01) strategy to break up the desired range of historical data into chunks of 8000 observations. 
I then employed the principles of [tidy data](https://vita.had.co.nz/papers/tidy-data.pdf) to combine everything into a convenient format for future analysis!



