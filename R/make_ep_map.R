
##############################
# Dependencies & Connection Settings
##############################

library(sp)
library(raster)
library(maptools)
library(data.table)
library(ggplot)
library(rgdal)
library(usmap)
library(rgeos)
library(gridExtra)

##############################
# Load data
##############################

meta.df <- read.csv('data/meta.csv')
im.sp <- SpatialPoints(meta.df[,c('lon', 'lat')])
rs <- raster('geodata/GRAY_HR_SR/GRAY_HR_SR.tif')
data(wrld_simpl)
states.spdf <- readOGR("geodata/usstates", "cb_2017_us_state_500k")

##############################
# Determine most popular countries
##############################

meta.dt <- data.table(meta.df)
ccount.dt <- meta.dt[, list(count = length(id)), by = country_name]
ccount.dt <- ccount.dt[order(ccount.dt$count, decreasing = FALSE),]
ccount.dt$prop <- ccount.dt$count/sum(ccount.dt$count)
ccount.dt <- tail(ccount.dt, 10)
ccount.df <- as.data.frame(ccount.dt)
ccount.dt$cfactor <- factor(x = ccount.dt$country_name, levels = ccount.dt$country_name)

##############################
# Plot pretty map
##############################

scale <- 0.075
png('plots/map.png', width = round(ncol(rs)*scale), height = round(nrow(rs)*scale))
par(mar = c(0,0,0,0), mai = c(0,0,0,0))
plot(rs, col = grey(seq(0, 0.5, length = 100)), legend=FALSE, axes=FALSE, box=FALSE)
plot(wrld_simpl, add = TRUE, col = NA, border = grey(0.9), lwd = 0.5)
plot(im.sp, add = TRUE, col =  adjustcolor("red", alpha.f = 0.5), pch = 16, cex = 0.8)
dev.off()

##############################
# Plot most popular countries barchart
##############################

p <- ggplot(data=as.data.frame(ccount.dt), aes(x=cfactor, y=prop)) +
  geom_bar(stat="identity") + coord_flip() + ylab("% of Submissions") + xlab("")
ggsave('plots/bar.png', plot = p, width = 4, height = 4)


##############################
# 'Scenicness' of US States
##############################

## Contiguous United States
states.spdf <- states.spdf[!(states.spdf$NAME %in% c("Alaska", "Hawaii", 
                                                     "United States Virgin Islands", 
                                                     "Commonwealth of the Northern Mariana Islands", 
                                                     "American Samoa", 
                                                     "Puerto Rico", "Guam")),]
states.spdf@data <- states.spdf@data[,c("NAME", "STUSPS", "ALAND")]
names(states.spdf) <- c("name", "abbr", "area")
states.spdf$area <- as.numeric(as.character(states.spdf$area))
pop.df <- as.data.frame(statepop)
states.spdf@data <- merge(states.spdf@data, pop.df, by = "abbr", all.x = TRUE, all.y = FALSE, sort = FALSE)

## Image count per capita and per area
intrs.mat <- gIntersects(states.spdf, im.sp, byid = TRUE)
count <- apply(intrs.mat, 2, sum)
states.spdf$imcount <- count
states.spdf$im_pc <- states.spdf$imcount / (states.spdf$pop_2015/100000)
states.spdf$im_pa <- states.spdf$imcount / (states.spdf$area/1000000)

spplot(states.spdf, zcol = "im_pc", main = "Images per 100k residents")
spplot(states.spdf, zcol = "im_pa", main = "Images per 1m square km")

gridExtra::grid.arrange(spplot(states.spdf, zcol = "im_pc", main = "Images per 100k residents"), 
                        spplot(states.spdf, zcol = "im_pa", main = "Images per 1m square km"))



