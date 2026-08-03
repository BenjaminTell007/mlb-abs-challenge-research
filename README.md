# MLB ABS Challenge Research

A statistical model for MLB's Automated Ball-Strike (ABS) challenge system: predicting the probability that an umpire's ball/strike call gets overturned on review, and using that prediction to build an expected-value decision rule for when a team should use a challenge.

## Data

Pitch-by-pitch data was pulled from MLB's Statcast system using the [`baseballr`](https://billpetti.github.io/baseballr/) R package (`statcast_search()`), covering the 2026 regular season from March 26 through May 18 (Petti & Gilani, 2024). The raw dataset contained one row per pitch thrown, including continuous pitch location coordinates (`plate_x`, `plate_z`), discrete count/outs/inning variables, and a categorical description of whether each pitch was called a strike or ball.

The data was filtered to called pitches only — pitches where the batter didn't swing and the umpire was forced to make a call. Swings, fouls, and balls put into play were excluded because they aren't affected by ABS.

## Feature Engineering

**ABS strike zone boundary.** The ABS zone is 17 inches wide, centered on home plate (MLB, 2026). Because a pitch is ruled a strike if any part of the ball crosses any part of the zone, the ball's radius (~1.45 in) is added to all boundaries (West, 2026). Horizontally, this gives an effective half-width of 0.829 ft. Vertically, the ball radius is added to `sz_top` and subtracted from `sz_bot`, so a pitch clipping the top or bottom edge of the zone still counts as a strike. Batter-specific vertical boundaries account for differences in height and stance across players.

**Umpire correctness.** Each pitch is classified as a correct or incorrect call by comparing the umpire's decision to the ABS zone: a call is correct if a called strike landed in the zone, or a called ball landed outside it.

**Count and outs.** Balls and strikes are converted into a single count string (e.g., `"2-1"`) to join against a run-expectancy table; outs are converted to an integer.

## Run Expectancy

Run expectancy (RE) values — average runs expected to score from each count state — come from Tango's RE matrix (Tango, n.d.). Walks and strikeouts get separate terminal RE values since they end the at-bat rather than transition to another count.

For each pitch, the count that would have resulted had the umpire's call been flipped (i.e., a successful challenge) is computed, and the RE of that flipped count is joined against the RE of the actual count. The difference (`re_delta = re_flipped - count_re`) is positive when the umpire's call hurt the batter, and negative when it helped them.

## Logistic Regression Model

A binary logistic regression predicts the probability that an umpire's call was incorrect (`p_overturn`), following the general approach of Danielson et al. (2024) and Deshpande & Wyner (2017) — though here the correct/incorrect label is unambiguous rather than estimated, since ABS provides the true pitch location relative to the zone.

Predictors:
- Horizontal distance outside the zone
- Vertical distance above the zone top
- Vertical distance below the zone bottom
- Ball count and strike count (to account for count-dependent umpire bias documented in Deshpande & Wyner, 2017)

**Assumption checks** (following Kassambara, 2018):
- Binary outcome — satisfied by construction
- Independent observations — each row is a single called pitch
- Linearity in the log-odds — verified via smoothed plots of each predictor against the log-odds, no systematic departures
- No multicollinearity — assessed via VIF (Fox & Weisberg, 2019); an initial combined distance-from-edge term produced VIF > 100 and was dropped, leaving a final model with VIF < 1.2
- No influential observations — assessed via Cook's distance and standardized residuals

## Expected Value & Decision Rule

The expected value of using a challenge is:

```
EV = P(overturn) × re_delta
```

A challenge is recommended when `EV` exceeds a `save_value` — the opportunity cost of using a challenge now rather than saving it for a potentially higher-value situation later. `save_value` decreases as the game progresses (0.05 through inning 6, 0.03 through inning 8, 0.01 from inning 9 on), since fewer future opportunities remain to use it. These save values are estimates; a more rigorous approach would compute the actual expected value of future challenge opportunities, which is beyond the scope of this project.

## Results

**Figure 1 — Overturn probability by pitch location** (2026 season, March 26 – May 18): predicted overturn probability peaks near the horizontal and vertical edges of the ABS zone, consistent with borderline pitches being the ones most likely to be miscalled. Pitches well inside or outside the zone approach near-zero overturn probability.

![Overturn probability heatmap](figures/fig1_overturn_probability.png)

**Figure 2 — Expected value of challenging by count and location**, for the four highest-leverage counts (3-2, 3-1, 0-2, 2-2): expected value is highest along the zone perimeter, where overturn probability is elevated. The 3-2 panel shows the largest magnitude, consistent with the high run-expectancy swing on full-count outcomes — a borderline 3-2 pitch in the highest-value bins carries an expected run value above 0.06 runs.

![Expected value by count](figures/fig2_expected_value_by_count.png)

## Repository Contents

- `abs.R` — full pipeline: data pull, feature engineering, run expectancy, model fitting, assumption checks, decision rule, visualizations
- `data/raw/called_pitches_2026.csv` — cached Statcast pull (called pitches only)
- `data/processed/df_final.rds` — engineered feature set
- `outputs/model_logit.rds` — fitted logistic regression model
- `figures/` — final versions of both plots

## References

- Danielson, G., Desai, S., Ehmann, Z., Sharma, O., & Smith, R. (2024). *Inside the strike zone: MLB umpire accuracy factors* [Undergraduate research poster]. University of North Carolina at Chapel Hill, Office for Undergraduate Research.
- Deshpande, S. K., & Wyner, A. (2017). A hierarchical Bayesian model of pitch framing. *Journal of Quantitative Analysis in Sports, 13*(3), 95–112. https://doi.org/10.1515/jqas-2017-0027
- Fox, J., & Weisberg, S. (2019). *An R companion to applied regression* (3rd ed.). Sage.
- Kassambara, A. (2018). *Logistic regression assumptions and diagnostics in R*. STHDA.
- MLB Baseball Savant. (2026). *Automatic ball-strike system*. https://baseballsavant.mlb.com/abs
- Petti, B., & Gilani, S. (2024). *baseballr: Acquiring and analyzing baseball data* (R package version 1.6.0.9002). https://billpetti.github.io/baseballr/
- Tango, T. (n.d.). *How are runs really created*. TangoTiger.net. https://tangotiger.net/runscreated.html
- West, C. (2026, March 3). *ABS: The math of a strike: How geometry defines the new MLB strike zone*. https://www.chriswest.tech/article/the_math_of_a_strike
- Wickham, H. (2016). *ggplot2: Elegant graphics for data analysis*. Springer-Verlag.
- Wickham, H., François, R., Henry, L., Müller, K., & Vaughan, D. (2023). *dplyr: A grammar of data manipulation* (R package version 1.2.1).
- Wickham, H., & Seidel, D. (2022). *scales: Scale functions for visualization* (R package version 1.4.0).
