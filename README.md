# MLB ABS Challenge Research

MLB's new Automated Ball-Strike (ABS) challenge system lets teams challenge umpire calls a limited number of times per game. This project builds a model to answer: **when is a challenge actually worth using?**

Using 2026-season Statcast data, I trained a logistic regression to predict the probability that a given umpire call would get overturned by ABS, then combined that with run-expectancy data to compute the expected run value of challenging any given pitch — and derived a simple decision rule for when a challenge is worth it versus saving it for later.

## Key Result

Expected value is highest for borderline pitches in high-leverage counts. A borderline call in a full count (3-2) carries an expected value above **+0.06 runs** if challenged — the single highest-value challenge situation identified in the data.

## Overturn Probability by Pitch Location

Predicted probability that an umpire's call gets overturned, by where the pitch crossed the plate. Risk is highest right at the edge of the strike zone, where the human eye is least reliable.

![Overturn probability heatmap](figures/fig1_overturn_probability.png)

## Expected Value by Count and Location

Expected run value of challenging, broken out by the four highest-leverage counts. The 3-2 count carries the largest swing, since a successful challenge there can turn a strikeout into a walk (or vice versa).

![Expected value by count](figures/fig2_expected_value_by_count.png)

## How It Works

1. Pull called-pitch data from Statcast (`baseballr`)
2. Engineer the ABS zone boundary (17" wide + ball radius, batter-specific vertical bounds) and label each call correct/incorrect
3. Join each pitch to Tango's run-expectancy matrix, both for the actual count and the count that would result if the call were overturned
4. Fit a logistic regression predicting overturn probability from pitch location and count
5. Compute `EV = P(overturn) × run_expectancy_delta` and flag a challenge as worth it when `EV` exceeds the opportunity cost of saving it for later

Full write-up, model diagnostics, and citations: **[docs/METHODOLOGY.md](docs/METHODOLOGY.md)**

## Tech

R · dplyr · ggplot2 · baseballr · logistic regression (glm)

## Repository Contents

- `abs.R` — full pipeline: data pull, feature engineering, run expectancy, model fitting, assumption checks, decision rule, visualizations
- `data/raw/called_pitches_2026.csv` — cached Statcast pull (called pitches only)
- `data/processed/df_final.rds` — engineered feature set
- `outputs/model_logit.rds` — fitted logistic regression model
- `figures/` — final plots
- `docs/METHODOLOGY.md` — detailed methodology, model diagnostics, and references
