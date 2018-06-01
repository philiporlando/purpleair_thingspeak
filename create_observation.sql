create table observation (
    created_at varchar(20)
    --,PRIMARY KEY(created_at, id, sensor, entry_id, label) 
    --,entry_id varchar(20)
    ,id varchar(4)
    ,sensor char(1)
    ,label varchar(100)
    ,pm1_0_atm numeric
    ,pm2_5_atm numeric
    ,pm10_0_atm numeric
    ,pm1_0_cf_1 numeric 
    ,pm2_5_cf_1 numeric
    ,pm10_0_cf_1 numeric
    ,p_0_3_um numeric
    ,p_0_5_um numeric
    ,p_1_0_um numeric
    ,p_2_5_um numeric
    ,p_5_0_um numeric
    ,p_10_0_um numeric
    ,geom varchar(50)
);
