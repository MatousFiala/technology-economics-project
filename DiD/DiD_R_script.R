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

data_rides_started <- read.csv("../data/daily_rides_started.csv")
data_rides_ended <- read.csv("../data/daily_rides_ended.csv")

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
  mutate(
    rides_started = ifelse(is.na(rides_started), 0, rides_started),
    rides_ended   = ifelse(is.na(rides_ended), 0, rides_ended)
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

### daily
### did twfe

did_static_end_log <- feols(
  log(rides_ended) ~ did_interaction | station_id + date,
  data = data_daily,
  cluster = ~station_id
  )
summary(did_static_end_log)

did_static_start_log <- feols(
  log(rides_started) ~ did_interaction | station_id + date,
  data = data_daily,
  cluster = ~station_id
)
summary(did_static_start_log)

did_static_end <- feols(
  rides_ended ~ did_interaction | station_id + date,
  data = data_daily,
  cluster = ~station_id
)
summary(did_static_end)

did_static_start <- feols(
  rides_started ~ did_interaction | station_id + date,
  data = data_daily,
  cluster = ~station_id
)
summary(did_static_start)

did_static_net <- feols(
  rides_net ~ did_interaction | station_id + date,
  data = data_daily,
  cluster = ~station_id
)
summary(did_static_net)

etable(
  did_static_start_log, did_static_end_log, did_static_net,
  tex = TRUE,                              
  file = "outputs/tables/did_static_daily.tex", 
  replace = TRUE,
  #style.tex = style.tex("aer"),
  headers = list(
    "Dependent Variable:" = c(
      "Rides Started (Log)",
      "Rides Ended (Log)",
      "Net Inflows (Levels)"
    )
  ),
  dict = c(did_interaction = "Toll Area $\\times$ Post"), 
  extralines = list(
    "_-Station Fixed Effects" = c("Yes", "Yes", "Yes"),
    "_-Date Fixed Effects"    = c("Yes", "Yes", "Yes")
  ),
  title = "Daily Difference-in-Differences Estimates: Congestion Pricing Impact",
  label = "tab:did_static_daily",
  fitstat = c("n", "r2", "ar2")
)

#extended table - sensitivity

etable(
  did_static_start_log, did_static_end_log, did_static_start, did_static_end, did_static_net,
  tex = TRUE,                              
  file = "outputs/tables/did_static_daily_ext.tex", 
  replace = TRUE,
  #style.tex = style.tex("aer"),
  headers = list(
    "Dependent Variable:" = c(
      "Rides Started (Log)",
      "Rides Ended (Log)",
      "Rides Started (Levels)", 
      "Rides Ended (Levels)", 
      "Net Inflows (Levels)"
    )
  ),
  dict = c(did_interaction = "Toll Area $\\times$ Post"), 
  extralines = list(
    "_-Station Fixed Effects" = c("Yes", "Yes", "Yes", "Yes", "Yes"),
    "_-Date Fixed Effects"    = c("Yes",  "Yes", "Yes", "Yes", "Yes")
  ),
  title = "Daily Difference-in-Differences Estimates: Congestion Pricing Impact",
  label = "tab:did_static_daily",
  fitstat = c("n", "r2", "ar2")
)


#weekly

did_static_w_start_log <- feols(
  log(weekly_rides_started) ~ did_interaction | station_id + week_start,
  data = data_weekly,
  cluster = ~station_id
)
summary(did_static_w_start_log)

did_static_w_end_log <- feols(
  log(weekly_rides_ended) ~ did_interaction | station_id + week_start,
  data = data_weekly,
  cluster = ~station_id
)
summary(did_static_w_end_log)

did_static_w_end <- feols(
  weekly_rides_ended ~ did_interaction | station_id + week_start,
  data = data_weekly,
  cluster = ~station_id
)
summary(did_static_w_end)

did_static_w_start <- feols(
  weekly_rides_started ~ did_interaction | station_id + week_start,
  data = data_weekly,
  cluster = ~station_id
)
summary(did_static_w_start)


did_static_w_net <- feols(
  weekly_rides_net ~ did_interaction | station_id + week_start,
  data = data_weekly,
  cluster = ~station_id
)
summary(did_static_w_net)


#extended table weekly - sensitivity

etable(
  did_static_w_start_log, did_static_w_end_log, did_static_w_start, did_static_w_end, did_static_w_net,
  tex = TRUE,                              
  file = "outputs/tables/did_static_weekly_ext.tex", 
  replace = TRUE,
  #style.tex = style.tex("aer"),
  headers = list(
    "Dependent Variable:" = c(
      "Rides Started (Log)",
      "Rides Ended (Log)",
      "Rides Started (Levels)", 
      "Rides Ended (Levels)", 
      "Net Inflows (Levels)"
    )
  ),
  dict = c(did_interaction = "Toll Area $\\times$ Post"), 
  extralines = list(
    "_-Station Fixed Effects" = c("Yes", "Yes", "Yes", "Yes", "Yes"),
    "_-Date Fixed Effects"    = c("Yes",  "Yes", "Yes", "Yes", "Yes")
  ),
  title = "Weekly Difference-in-Differences Estimates: Congestion Pricing Impact",
  label = "tab:did_static_daily",
  fitstat = c("n", "r2", "ar2")
)


#event study

event_study_weekly_net <- feols(
  weekly_rides_net ~ i(weeks_to_toll, toll_area, ref =  -1) | station_id + week_start,
  data = data_weekly,
  cluster = ~station_id
)
iplot(event_study_weekly_net)


#monthly

# event_study_seasonal <- feols(
#   asinh(weekly_rides_net) ~ i(months_to_toll, toll_area, ref = -1) | station_month_i + week_start,
#   data = data_weekly,
#   cluster = ~station_id
# )
# 
# summary(event_study_seasonal)
# iplot(event_study_seasonal)


event_study_monthly_net <- feols(
  weekly_rides_net ~ i(months_to_toll, toll_area, ref = -1) | station_id + month_num,
  data = data_weekly,
  cluster = ~station_id
)
iplot(event_study_monthly_net)


# did_static_m <- feols(
#   asinh(weekly_rides_net) ~ did_interaction | station_month_i + week_start,
#   data = data_weekly,
#   cluster = ~station_id
# )
# summary(did_static_m)
# 
# did_static_m2 <- feols(
#   asinh(weekly_rides_net) ~ did_interaction | station_id + month_num,
#   data = data_weekly,
#   cluster = ~station_id
# )
# summary(did_static_m2)


### outputs

if (!dir.exists("outputs")) dir.exists("outputs")
if (!dir.exists("outputs/figures")) dir.create("outputs/figures", recursive = TRUE)
if (!dir.exists("outputs/tables")) dir.create("outputs/tables", recursive = TRUE)

# plot
pdf("outputs/figures/event_study_monthly.pdf", width = 8, height = 5)

iplot(event_study_monthly_net,
      main = "Effect of Congestion Toll on Net Bike Inflows",
      xlab = "Months Relative to Toll Activation (Jan 2025)",
      ylab = "Coefficient Estimate",
      col = "darkblue", 
      pt.join = TRUE)
abline(h = 0, col = "red", lty = 2)

dev.off()

pdf("outputs/figures/event_study_weekly.pdf", width = 8, height = 5)

iplot(event_study_weekly_net,
      main = "Effect of Congestion Toll on Net Bike Inflows",
      xlab = "Weeks Relative to Toll Activation (Jan 2025)",
      ylab = "Coefficient Estimate",
      col = "darkblue", 
      pt.join = TRUE)
abline(h = 0, col = "red", lty = 2)

dev.off()

# # export static models to table file
# etable(
#   XXXX
#   tex = TRUE,                              
#   file = "outputs/tables/did_static_results.tex", 
#   replace = TRUE,                          
#   dict = c(did_interaction = "Toll Area $\\times$ Post",
#            weekly_rides_net = "Net Weekly Rides (asinh)"), 
#   title = "Difference-in-Differences Estimates: Congestion Pricing Impact",
#   label = "tab:did_static",
#   fitstat = c("n", "r2", "adjr2") 
# )
#  

# need to select some models as the prefered ones





