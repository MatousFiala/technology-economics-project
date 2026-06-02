library(tidyverse)
library(sf)
library(lubridate)
library(tis)
library(fixest)

data_stations_raw <- readRDS("../data/nyc_bike_stations.rds")

data_stations <- data_stations_raw |>
  filter(!is.na(signed_distance_from_toll_m)) |>
  rename("station_name" = "start_station_name", 
         "toll_dist" = "signed_distance_from_toll_m"
         )


head(data_stations)
summary(data_stations)

stations_to_keep <- data_stations$station_name

data_rides_started <- read.csv("./data/daily_rides_started.csv")
data_rides_ended <- read.csv("./data/daily_rides_ended.csv")

head(data_rides_started)
summary(data_rides_started)
min(data_rides_started$date)
max(data_rides_started$date)

head(data_rides_ended)
summary(data_rides_ended)
min(data_rides_ended$date)
max(data_rides_ended$date)


data_rides <- data_rides_started |>
  full_join(
    data_rides_ended,
    by = c(
    "date" = "date",
    "start_station_id" = "end_station_id", 
    "start_station_name" = "end_station_name"
    ), 
    suffix = c("_started", "_ended")
    ) |>
  rename(
    "station_id" = "start_station_id",
    "station_name" = "start_station_name"
    ) |>
  mutate(
    date = as.Date(date), 
    day_of_week = wday(date), 
    is_weekend = ifelse(day_of_week %in% c("1", "7"), TRUE, FALSE), 
    is_holiday = isHoliday(date), 
    is_workday = isBusinessDay(date)
    ) |>
  filter(
    date > as.Date("2023-12-31"),
    station_name %in% stations_to_keep, 
    !is.na(rides_started), 
    !is.na(rides_ended)
    ) |>
  mutate(
    toll_effective = ifelse(date >= as.Date("2025-01-05"), 1, 0), 
    rides_net = rides_ended - rides_started
    )

head(data_rides)
summary(data_rides)

boxplot(data_rides$rides_started)
boxplot(data_rides$rides_ended)

data_daily <- data_rides |>
  left_join(data_stations, by = c("station_name")) |>
  mutate(
    toll_area = ifelse(toll_dist > 0, 1, 0), 
    did_interaction = toll_effective * toll_area
    )

head(data_daily)
summary(data_daily)

filter(data_daily, date == "2025-01-05")
as.Date(as.Date("2025-01-05") - 6)

data_weekly <- data_daily |>
  mutate(
    week_start = floor_date(date, unit = "week"), 
  ) |>
  group_by(station_name, station_id, week_start) |>
  summarize(
    weekly_rides_started = sum(rides_started),
    weekly_rides_ended = sum(rides_ended), 
    weekly_rides_net = sum(rides_net),
    toll_dist = first(toll_dist), 
    toll_area = first(toll_area), 
    days_recorded = n(), 
    .groups =  "drop"
  ) |>
  filter(
    days_recorded == 7
  ) |>
  mutate(
    toll_effective = ifelse(week_start >= as.Date("2025-01-05"), 1, 0), 
    did_interaction = toll_effective * toll_area, 
    weeks_to_toll = as.integer((week_start - as.Date("2025-01-05")) / 7), 
    months_to_toll = round(weeks_to_toll / 4),     
    month_num = month(week_start),
    station_month_i = paste0(station_id, "_", month_num)
  )

head(data_weekly)
summary(data_weekly)

##### regressions

### DiD

did_static_simple <- feols(
  rides_ended ~ did_interaction | station_id,
  data = data_daily,
  cluster = ~station_id
)
summary(did_static_simple)

did_static <- feols(
  rides_ended ~ did_interaction | station_id + date,
  data = data_daily,
  cluster = ~station_id
  )
summary(did_static)

did_static_controls <- feols(
  rides_ended ~ did_interaction + is_workday | station_id,
  data = data_daily,
  cluster = ~station_id
)
summary(did_static_controls)

#weekly

did_static_simple_w <- feols(
  asinh(weekly_rides_net) ~ did_interaction | station_id,
  data = data_weekly,
  cluster = ~station_id
)
summary(did_static_simple_w)

did_static_w <- feols(
  asinh(weekly_rides_net) ~ did_interaction | station_id + week_start,
  data = data_weekly,
  cluster = ~station_id
)
summary(did_static_w)

#event study

event_study_model <- feols(
  asinh(weekly_rides_net) ~ i(weeks_to_toll, toll_area, ref =  -1) | station_id + week_start,
  data = data_weekly,
  cluster = ~station_id
)
iplot(event_study_model)


#monthly

event_study_seasonal <- feols(
  asinh(weekly_rides_net) ~ i(months_to_toll, toll_area, ref = -1) | station_month_i + week_start,
  data = data_weekly,
  cluster = ~station_id
)

summary(event_study_seasonal)
iplot(event_study_seasonal)


event_study_monthly<- feols(
  asinh(weekly_rides_net) ~ i(months_to_toll, toll_area, ref = -1) | station_id + month_num,
  data = data_weekly,
  cluster = ~station_id
)

summary(event_study_monthly)
iplot(event_study_monthly)


did_static_m <- feols(
  asinh(weekly_rides_net) ~ did_interaction | station_month_i + week_start,
  data = data_weekly,
  cluster = ~station_id
)
summary(did_static_m)

did_static_m2 <- feols(
  asinh(weekly_rides_net) ~ did_interaction | station_id + month_num,
  data = data_weekly,
  cluster = ~station_id
)
summary(did_static_m2)









