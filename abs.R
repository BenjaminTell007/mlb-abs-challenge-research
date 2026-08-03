library(baseballr)
library(dplyr)

#------------data-------------------


#Pull data from 2026 season 
raw <- statcast_search(start_date = "2026-03-26", end_date = "2026-05-18", player_type = "batter")


called <- raw %>%
  filter(description %in% c("called_strike", "ball"))

#Save it so then we don't have to pull everytime
write.csv(called, "data/raw/called_pitches_2026.csv", row.names = FALSE)

#-----------Feature engineering----------------


# ABS zone: 17 inches wide, centered on plate; plate_x in feet from center
zone_half_width <- (8.5 + 1.45) / 12   # 0.829 ft — plate half-width + ball radius
ball_radius     <- 1.45 / 12           # 0.121 ft — added to vertical boundaries

df <- called %>%
  mutate(
    # Distance from zone edge1
    dist_x     = pmax(abs(plate_x) - zone_half_width, 0),
    dist_z_top = pmax(plate_z - sz_top, 0),
    dist_z_bot = pmax(sz_bot - plate_z, 0),
    dist_from_edge = sqrt(dist_x^2 + pmax(dist_z_top, dist_z_bot)^2),
    
    # Was the umpire correct?
    in_abs_zone = (abs(plate_x) <= zone_half_width) &
      (plate_z >= sz_bot) &
      (plate_z <= sz_top),
    
    ump_correct = case_when(
      description == "called_strike" &  in_abs_zone  ~ TRUE,
      description == "ball"          & !in_abs_zone  ~ TRUE,
      TRUE                                            ~ FALSE
    ),
    ump_wrong = !ump_correct,
    
    # Count
    outs  = as.integer(outs_when_up),
    count = paste0(balls, "-", strikes)
  )



#-------------Run Expectancy--------------------

#Tango's RE Matrix
count_run_value <- data.frame(
  count = c("0-0","1-0","2-0","3-0","0-1","1-1","2-1","3-1","0-2","1-2","2-2","3-2"),
  re    = c(0.000, 0.032, 0.080, 0.141,-0.037,-0.012, 0.030, 0.090,-0.082,-0.063,-0.033, 0.018)
)

#Count value if call is flipped
df <- df %>%
  mutate(
    flipped_count = case_when(
      description == "called_strike" & balls == 3   ~ "walk",
      description == "ball"          & strikes == 2 ~ "strikeout",
      description == "called_strike"                ~ paste0(balls + 1, "-", strikes),
      description == "ball"                         ~ paste0(balls, "-", strikes + 1),
      TRUE                                          ~ count
    )
  )

# Run value of walk and strikeout outcomes since this is not factored above
terminal_re <- data.frame(
  flipped_count = c("walk", "strikeout"),
  re_flipped    = c(0.330, -0.270)
)


#Combine them together 
count_re_extended <- rbind(
  data.frame(flipped_count = count_run_value$count, re_flipped = count_run_value$re),
  terminal_re
)

# Join to get current count RE and flipped count RE
df <- df %>%
  left_join(count_run_value %>% rename(count_re = re), by = "count") %>%
  left_join(count_re_extended, by = "flipped_count") %>%
  mutate(re_delta = re_flipped - count_re)







#_________________Model____________________

#Logistic regression
model_logit <- glm(
  ump_wrong ~ dist_x + dist_z_top + dist_z_bot +
    balls + strikes,
  data   = df %>% filter(description %in% c("called_strike", "ball")),
  family = binomial(link = "logit")
)


# Predicted overturn probability for every pitch
df$p_overturn <- predict(model_logit, newdata = df, type = "response")


summary(model_logit)


#------------Model Asumptions-----------------------

#Assumption 1: Binary Outcome
#binary outcome satisfied by construction (ump_wrong is TRUE/FALSE)
library(car)
library(broom)


# Assumption 2: linearity in log-odds
logit_vals <- log(fitted(model_logit) / (1 - fitted(model_logit)))
model_df   <- model.frame(model_logit) %>% mutate(logit = logit_vals)
par(mfrow = c(1, 3))
for (var in c("dist_x", "dist_z_top", "dist_z_bot"))
  scatter.smooth(model_df[[var]], model_df$logit, xlab = var, ylab = "logit(p)")
par(mfrow = c(1, 1))

# Assumption 3: no influential values
plot(model_logit, which = 4, id.n = 3)
augment(model_logit) %>% filter(abs(.std.resid) > 3)

# Assumption 4: no multicollinearity
vif(model_logit)

dir.create("outputs", recursive = TRUE, showWarnings = FALSE)
saveRDS(model_logit, "outputs/model_logit.rds")




#---------------Decision Rule----------------



df <- df %>%
  mutate(
    # Expected run value of challenging
    ev_challenge = p_overturn * re_delta,
    
    # Save value decreases as game progresses (fewer future opportunities to use challenge)
    save_value = case_when(
      inning <= 6L ~ 0.05,
      inning <= 8L ~ 0.03,
      inning >= 9L ~ 0.01,
      TRUE         ~ 0.03
    ),
    
    # Challenge recommendation
    should_challenge = ev_challenge > save_value
  )


#-------------Visualizations--------


library(ggplot2)
library(scales)


zone_xmin <- -(17 / 2) / 12
zone_xmax <-  (17 / 2) / 12
zone_ymin <- mean(df$sz_bot, na.rm = TRUE)
zone_ymax <- mean(df$sz_top, na.rm = TRUE)

# Plot 1: Overturn probability heatmap
p1 <- ggplot(df, aes(x = plate_x, y = plate_z, z = p_overturn)) +
  stat_summary_2d(bins = 30, fun = mean) +
  scale_fill_gradient2(low = "steelblue", mid = "white", high = "firebrick",
                       midpoint = 0.15, labels = percent_format(accuracy = 1)) +
  annotate("rect", xmin = zone_xmin, xmax = zone_xmax,
           ymin = zone_ymin, ymax = zone_ymax,
           fill = NA, color = "black", linewidth = 1) +
  coord_fixed(xlim = c(-2, 2), ylim = c(0, 5)) +
  labs(title = "Overturn Probability by Pitch Location",
       x = "Horizontal Location (ft from center)",
       y = "Vertical Location (ft)", fill = "P(Overturn)") +
  theme_minimal()

p1


# Plot 2: Expected value heatmap by count
p2_data <- df %>% 
  filter(count %in% c("3-2","3-1","0-2","2-2"), !is.na(ev_challenge)) %>%
  mutate(count = factor(count, levels = c("3-2","3-1","0-2","2-2")))

p2 <- ggplot(p2_data, aes(x = plate_x, y = plate_z, z = ev_challenge)) +
  stat_summary_2d(bins = 20, fun = mean) +
  scale_fill_gradient2(low = "steelblue", mid = "white", high = "firebrick",
                       midpoint = 0.02, labels = number_format(accuracy = 0.01)) +
  annotate("rect", xmin = zone_xmin, xmax = zone_xmax,
           ymin = zone_ymin, ymax = zone_ymax,
           fill = NA, color = "black", linewidth = 0.8) +
  facet_wrap(~count, ncol = 2, labeller = labeller(count = count_labels)) +
  coord_fixed(xlim = c(-2, 2), ylim = c(0.5, 4.5)) +
  labs(title = "Expected Value of Challenging by Count and Location",
       x = "Horizontal Location (ft)", y = "Vertical Location (ft)", fill = "EV (runs)") +
  theme_minimal()

p2

citation("baseballr")
  

version$version.string        
RStudio.Version()$version     
packageVersion("ggplot2")
packageVersion("baseballr")
packageVersion("dplyr")
packageVersion("car")
packageVersion("broom")
packageVersion("scales")
packageVersion("dplyr")


