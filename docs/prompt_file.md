# Prompt File

# Compare weight-length relationships
- The goal of this analysis is to compare weight at length between hatchery and wild-origin pink salmon.
- The data can be found in pink_LW_oto_updated.csv.
- The analysis should only include origin.certain == "y".
- The analysis should exclude fish collected in May.
- The model should include origin and year as fixed effects, and beach seine identity as a random effect.
- Some sets are missing a set number. For these, create a unique set number based on unique year-bay-site combinations.
- A linear mixed-effects approach should be used.
- Write the code for this analysis in a new R script, run the model and diagnostic checks, and report results in a table and a figure. 

# Iterate - June/August
- Refit the June-August model without a year term.
- Compare with the full model with AICc.


# Iterate - May
- Run a similar model fit only to data for fish collected in May 2023.
- This model will only include hatchery/wild origin as a fixed effect, with no year effect or random effect.

# Plot both models
- Create a barplot of the estimated coefficient for hatchery and wild fish, including 95% CI error bars.
- On the left, include the results of the May model.
- On the right, include the results of the full June-August model (including year as a covariate.)

# Save session info
- Save the information from the chat pane for this session in the docs folder.