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

### visualization

data_trends_plot <- data_weekly |>
  group_by(week_start, toll_area) |>
  summarize(
    avg_inflows = mean(weekly_rides_ended),
    avg_outflows = mean(weekly_rides_started),
    avg_net = mean(weekly_rides_net),
    .groups = "drop"
  ) |>
  mutate(
    group_label = ifelse(toll_area == 1, "Treated (Inside Toll Zone)", "Control (Outside Zone)"), 
    period = ifelse(week_start >= as.Date("2025-01-05"), "Post-Toll", "Pre-Toll")
  )

png("outputs/figures/parallel_trends_raw.png", width = 9, height = 5.5, units = "in", res = 300)

ggplot(data_trends_plot, aes(x = week_start, y = log1p(avg_inflows), group = group_label, color = group_label)) +
  geom_point(size = 1.5, alpha = 0.4) +
  geom_smooth(
    aes(group = interaction(group_label, period)), 
    method = "gam", 
    se = FALSE
  ) +
  geom_vline(xintercept = as.Date("2025-01-05"), linetype = "dashed", linewidth = 1, alpha = 0.8) +
  theme_minimal() +
  labs(
    title = "Raw Weekly Bike Inflows: Treated vs. Control Stations",
    x = "Timeline (Weekly Aggregation)",
    y = "Log of Average Weekly Rides Ended",
    color = "Station Group"
  ) +
  theme(legend.position = "bottom")
dev.off()


### plot of residuals

season_model <- feols(
  log1p(weekly_rides_ended) ~ 1 | station_month_i + week_start,
  data = data_weekly
)

data_weekly$rides_seasonally_adjusted <- residuals(season_model, na.rm = FALSE)

data_adjusted_trends <- data_weekly |>
  group_by(week_start, toll_area) |>
  summarize(
    avg_adjusted_rides = mean(rides_seasonally_adjusted),
    .groups = "drop"
  ) |>
  mutate(
    group_label = ifelse(toll_area == 1, "Treated (Inside Toll Zone)", "Control (Outside Zone)"),
    period = ifelse(week_start >= as.Date("2025-01-05"), "Post-Toll", "Pre-Toll")
  )


png("outputs/figures/parallel_trends_adjusted.png", width = 9, height = 5.5, units = "in", res = 300)

ggplot(data_adjusted_trends, aes(x = week_start, y = avg_adjusted_rides, color = group_label)) +
  geom_point(alpha = 0.4, size = 1.5) +
  geom_smooth(
    aes(group = interaction(group_label, period)),
    method = "gam",
    se = FALSE,
    linewidth = 1.2
  ) +
  geom_vline(xintercept = as.Date("2025-01-05"), linetype = "dashed", linewidth = 1, alpha = 0.8) +
  theme_minimal() +
  labs(
    title = "Seasonally Adjusted Parallel Trends (Residuals)",
    x = "Timeline (Weekly Aggregation)",
    y = "Log of Average Residual Weekly Rides",
    color = "Station Group"
  ) +
  theme(legend.position = "bottom")
dev.off()

##### regressions

### daily
### did twfe

did_static_end_log <- feols(
  log1p(rides_ended) ~ did_interaction | station_id + date,
  data = data_daily,
  cluster = ~station_id
  )
summary(did_static_end_log)

did_static_start_log <- feols(
  log1p(rides_started) ~ did_interaction | station_id + date,
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
  depvar = FALSE,
  headers = list(
    "Dependent Variable:" = c(
      "Rides Started (Log)",
      "Rides Ended (Log)",
      "Net Inflows (Levels)"
    )
  ),
  dict = c(did_interaction = "Toll Area $\\times$ Post"), 
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
  depvar = FALSE,
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
  title = "Daily Difference-in-Differences Estimates: Congestion Pricing Impact",
  label = "tab:did_static_daily",
  fitstat = c("n", "r2", "ar2")
)


#weekly

did_static_w_start_log <- feols(
  log1p(weekly_rides_started) ~ did_interaction | station_id + week_start,
  data = data_weekly,
  cluster = ~station_id
)
summary(did_static_w_start_log)

did_static_w_end_log <- feols(
  log1p(weekly_rides_ended) ~ did_interaction | station_id + week_start,
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
  depvar = FALSE, 
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

event_study_weekly_ended <- feols(
  log1p(weekly_rides_ended) ~ i(weeks_to_toll, toll_area, ref =  -1) | station_id + week_start,
  data = data_weekly,
  cluster = ~station_id
)
iplot(event_study_weekly_ended)


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


event_study_monthly_ended <- feols(
  log1p(weekly_rides_ended) ~ i(months_to_toll, toll_area, ref = -1) | station_id + month_num,
  data = data_weekly,
  cluster = ~station_id
)
iplot(event_study_monthly_ended)



### higher dimensionality

# did_static_m <- feols(
#    log(weekly_rides_started) ~ did_interaction | station_month_i + week_start,
#    data = data_weekly,
#    cluster = ~station_id
#  )
# summary(did_static_m)
# 
#  did_static_m <- feols(
#    weekly_rides_net ~ did_interaction | station_month_i + week_start,
#    data = data_weekly,
#    cluster = ~station_id
#  )
# summary(did_static_m)

# --- should be solved by did desing itself, but might include this as robustness check






### outputs

if (!dir.exists("outputs")) dir.exists("outputs")
if (!dir.exists("outputs/figures")) dir.create("outputs/figures", recursive = TRUE)
if (!dir.exists("outputs/tables")) dir.create("outputs/tables", recursive = TRUE)

# plot
png("outputs/figures/event_study_monthly.png", width = 8, height = 5, units = "in", res = 300)
iplot(event_study_monthly_net,
      main = "Effect of Congestion Toll on Net Bike Inflows",
      xlab = "Months Relative to Toll Activation (Jan 2025)",
      ylab = "Coefficient Estimate",
      col = "darkblue", 
      pt.join = TRUE)
abline(h = 0, col = "red", lty = 2)
dev.off()

png("outputs/figures/event_study_monthly_ended.png", width = 8, height = 5, units = "in", res = 300)
iplot(event_study_monthly_ended,
      main = "Effect of Congestion Toll on Bike Inflows",
      xlab = "Months Relative to Toll Activation (Jan 2025)",
      ylab = "Coefficient Estimate",
      col = "darkblue", 
      pt.join = TRUE)
abline(h = 0, col = "red", lty = 2)
dev.off()

png("outputs/figures/event_study_weekly.png", width = 8, height = 5, units = "in", res = 300)
iplot(event_study_weekly_net,
      main = "Effect of Congestion Toll on Net Bike Inflows",
      xlab = "Weeks Relative to Toll Activation (Jan 2025)",
      ylab = "Coefficient Estimate",
      col = "darkblue", 
      pt.join = TRUE)
abline(h = 0, col = "red", lty = 2)
dev.off()

png("outputs/figures/event_study_weekly_ended.png", width = 8, height = 5, units = "in", res = 300)
iplot(event_study_weekly_ended,
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





