# pull 3rd part purpleair data from json api
import json
import urllib
import requests
import time
from datetime import datetime
import calendar
import sys
import itertools
import os
import pandas as pd

file_name = "pa_id_key.txt"
dir_name = "/data/pa_id_key/"
full_path = os.getcwd() + "//" + dir_name + "//" + file_name
row = 0

d = datetime.utcnow()
unixtime = calendar.timegm(d.utctimetuple())

df = pd.DataFrame(columns=['datetime'
    ,'ID'
    ,'ParentID'
    ,'Label'
    ,'DEVICE_LOCATIONTYPE'
    ,'THINGSPEAK_PRIMARY_ID'
    ,'THINGSPEAK_PRIMARY_ID_READ_KEY'
    ,'THINGSPEAK_SECONDARY_ID'
    ,'THINGSPEAK_SECONDARY_ID_READ_KEY'
    ,'Lat'
    ,'Lon'
    ,'PM2_5Value'
    #,'LastSeen'
    ,'State'
    ,'Type'
    ,'Hidden'
    ,'Flag'
    ,'isOwner'
    ,'A_H'
    ,'temp_f'
    ,'humidity'
    ,'pressure'
    ,'AGE'
    ,'Stats'
    ])

print

## assigning PurpleAir API to url
url = "https://www.purpleair.com/json"

## GET request from PurpleAir API
try:
    r = requests.get(url)
    print '[*] Connecting to API...'
    print '[*] GET Status: ', r.status_code

except Exception as e:
    print '[*] Unable to connect to API...'
    print 'GET Status: ', r.status_code
    print e
print

try:
    ## parse the JSON returned from the request
    j = r.json()

except Exception as e:
    print '[*] Unable to parse JSON'
    print e

try:
    ##  iterate through entire dictionary
    for sensor in j['results']:

        df.loc[row] = pd.Series(dict(datetime = datetime.fromtimestamp(sensor['LastSeen'])
            ,ID = sensor['ID']
            ,ParentID = sensor['ParentID']
            ,Label = sensor['Label']
            ,DEVICE_LOCATIONTYPE = sensor['DEVICE_LOCATIONTYPE']
            ,THINGSPEAK_PRIMARY_ID = sensor['THINGSPEAK_PRIMARY_ID']
            ,THINGSPEAK_PRIMARY_ID_READ_KEY = sensor['THINGSPEAK_PRIMARY_ID_READ_KEY']
            ,THINGSPEAK_SECONDARY_ID = sensor['THINGSPEAK_SECONDARY_ID']
            ,THINGSPEAK_SECONDARY_ID_READ_KEY = sensor['THINGSPEAK_SECONDARY_ID_READ_KEY']
            ,Lat = sensor['Lat']
            ,Lon = sensor['Lon']
            ,PM2_5Value = sensor['PM2_5Value']
            #,LastSeen = sensor['LastSeen']
            ,State = sensor['State']
            ,Type = sensor['Type']
            ,Hidden = sensor['Hidden']
            ,Flag = sensor['Flag']
            ,isOwner = sensor['isOwner']
            ,A_H = sensor['A_H']
            ,temp_f = sensor['temp_f']
            ,humidity = sensor['humidity']
            ,pressure = sensor['pressure']
            ,AGE = sensor['AGE']
            ,Stats= sensor['Stats']
            )
        )

        print df.loc[[row]]
        row += 1
        df.to_csv(full_path, sep = ",", index = False, encoding = 'utf-8')
except Exception as e:
    print '[*] Error, no data was written to file'
    print e
