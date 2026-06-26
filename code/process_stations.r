source("~/R/scripts/utils.R")
library("sf")
library("nycgeo")
library("units")
library("lwgeom")

data <- read_csv("../data/202301-citibike-tripdata_1.csv")

ntas <- nyc_boundaries(geography =  "nta") %>% st_transform(st_crs("NAD83")) %>%
    select(nta_id, nta_name, borough_id, borough_name)

boroughs <- nyc_boundaries(geography =  "borough") %>% st_transform(st_crs("NAD83")) 

toll_line <- st_linestring(matrix(c(-73.958390, 40.758940, 
                       -73.993374, 40.773679),
             nrow = 2, byrow= T)) |>
            st_sfc(crs = st_crs("NAD83"))


nyc_boundaries(geography = "borough")[[1, 7]]

long_lat <- data %>%
    summarise(.by = start_station_name, lng = mean(start_lng, na.rm = T), lat = mean(start_lat, na.rm = T)) %>%
    filter(!is.na(lng), !is.na(lat)) %>%
    st_as_sf(coords = c("lng", "lat"), crs = st_crs("NAD83"))  %>%
    st_join(ntas) %>%
    mutate(toll_distance = if_else(borough_name == "Manhattan", as.numeric(st_distance(geometry, toll_line)), NA),
           nearest_point = st_endpoint(st_nearest_points(geometry, toll_line)),
           side_of_line = if_else(borough_name == "Manhattan", if_else(st_coordinates(geometry)[, "Y"] < st_coordinates(nearest_point)[,"Y"], 1, -1), NA),
           signed_distance_from_toll_m = round(side_of_line*toll_distance)
    ) %>%
    select(start_station_name, nta_name, borough_name, signed_distance_from_toll_m)

saveRDS(long_lat, "nyc_bike_stations.rds")



 d <- readRDS("nyc_bike_stations.rds")



ggplot(d) +
    geom_sf(data = st_crop(boroughs, st_bbox(d))) +
    geom_sf(aes(colour = signed_distance_from_toll_m)) +
    geom_sf(data = toll_line) +
    scale_colour_gradientn(colours = c("white", "darkred", "darkblue", "white"), 
                           values = c(0, 0.499, 0.500, 1),
                           limits = c(min(d$signed_distance_from_toll_m),max(d$signed_distance_from_toll_m))
                           ) +
    coord_sf() +
    theme_cp_map() +
    theme(legend.position = "right") +
    labs(colour = "Vzdálenost od\ndělící čáry (m)")

ggsave("stations_plot.png")



