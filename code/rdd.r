library(rdrobust)
library(tidyverse)
library(sf)

stations <- readRDS("./nyc_bike_stations.rds")
rides_ended <- read_csv("./daily_rides_ended.csv")
rides_started <- read_csv("./daily_rides_started.csv")

rdd_data <- rides_ended |>
    mutate(year_pre = date - years(1)) |>
    left_join(rides_ended, by = c("end_station_id", "end_station_name", "year_pre" = "date")) |>
    filter(!is.na(rides.y)) |>
    filter(abs(as.numeric(date - as_date("2025-01-05"))) < 5) |>
    inner_join(st_drop_geometry(stations), by = c("end_station_name" = "start_station_name")) |>
    filter(borough_name == "Manhattan") |>
    mutate(pre_reform = date < as_date("2025-01-05")) |>
    summarise(.by = c(pre_reform, end_station_id, end_station_name, borough_name, nta_name, signed_distance_from_toll_m), rides_now = sum(rides.x), rides_last_year = sum(rides.y)) |>
    mutate(log_yoy_diff = log(rides_now) - log(rides_last_year))


rdd <- rdrobust(y = rdd_data$log_yoy_diff, x = rdd_data$signed_distance_from_toll_m, c = 0)

summary(rdd)

rdplot(y = rdd_data$log_yoy_diff, x = rdd_data$signed_distance_from_toll_m, c = 0)

# -------------------- 

rdd_data_started <- rides_started |>
    mutate(year_pre = date - years(1)) |>
    left_join(rides_started, by = c("start_station_id", "start_station_name", "year_pre" = "date")) |>
    filter(!is.na(rides.y)) |>
    filter(abs(as.numeric(date - as_date("2025-01-05"))) < 5) |>
    inner_join(st_drop_geometry(stations), by = "start_station_name") |>
    filter(borough_name == "Manhattan") |>
    mutate(pre_reform = date < as_date("2025-01-05")) |>
    summarise(.by = c(pre_reform, start_station_id, start_station_name, borough_name, nta_name, signed_distance_from_toll_m), rides_now = sum(rides.x), rides_last_year = sum(rides.y)) |>
    mutate(log_yoy_diff = log(rides_now) - log(rides_last_year))


rdd_started <- rdrobust(y = rdd_data_started$log_yoy_diff, x = rdd_data_started$signed_distance_from_toll_m, c = 0)

summary(rdd)

rdplot(y = rdd_data_started$log_yoy_diff, x = rdd_data_started$signed_distance_from_toll_m, c = 0)
