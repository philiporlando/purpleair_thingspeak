create table if not exists observation (
    created_at character(20)
    ,entry_id character(20)
    ,sensor character(1)
    ,label character(50)
    ,id character(10)
    ,geom character (100)
    ,field character(50)
    ,value numeric
    )
