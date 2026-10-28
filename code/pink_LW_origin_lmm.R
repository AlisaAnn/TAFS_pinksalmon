# Compare weight at length between hatchery and wild-origin pink salmon
# Uses only fish with certain origin (origin.certain == "y")
# 1) June - August, 2022-2023: linear mixed-effects model
#    log(weight) ~ log(Length) + origin + year + (1 | set),
#    compared by AICc with the same model without year
# 2) May 2023 only: linear model log(weight) ~ log(Length) + origin
# Run from the project root (open pinksalmon.Rproj)

library(tidyverse)
library(lme4)
library(patchwork)

theme_set(theme_bw())

#### DATA ####
# missing values are coded as "." in the csv
pinks_raw <- read.csv("data/pink_LW_oto_updated.csv", na.strings = c(".", ""))

pinks <- pinks_raw %>%
  filter(origin.certain == "y",
         Month != "May") %>%
  mutate(origin = factor(hatch.wild, levels = c("wild", "hatchery")),
         Year_fac = factor(Year),
         log_L = log(Length),
         log_W = log(weight))

nrow(pinks)
table(pinks$origin, pinks$Year_fac)

# some sets are missing a set number - assign a unique number to each
# year-bay-site combination for these (starting at 1001 to avoid real set numbers)
sum(is.na(pinks$set))

new_sets <- pinks %>%
  filter(is.na(set)) %>%
  distinct(Year, Bay, Site) %>%
  arrange(Year, Bay, Site) %>%
  mutate(new_set = 1000 + row_number())
new_sets

pinks <- pinks %>%
  left_join(new_sets, by = c("Year", "Bay", "Site")) %>%
  mutate(set_id = factor(coalesce(set, new_set))) %>%
  dplyr::select(-new_set)

# check that every set falls within a single year and bay
pinks %>%
  group_by(set_id) %>%
  summarise(n_year = n_distinct(Year), n_bay = n_distinct(Bay)) %>%
  filter(n_year > 1 | n_bay > 1)

nlevels(pinks$set_id)
summary(as.vector(table(pinks$set_id))) # fish per set

#### MODEL ####
# origin and year as fixed effects, beach seine set as a random intercept
lmm <- lmer(log_W ~ log_L + origin + Year_fac + (1 | set_id), data = pinks, REML = TRUE)
summary(lmm)
anova(lmm)

# likelihood ratio tests for each fixed effect (ML fits)
lmm_ml <- update(lmm, REML = FALSE)
lrt <- drop1(lmm_ml, test = "Chisq")
lrt

# profile 95% confidence intervals
ci <- confint(lmm, method = "profile", signames = FALSE)
ci

#### DIAGNOSTICS ####
diag_dat <- pinks %>%
  mutate(fitted = fitted(lmm),
         resid = resid(lmm, type = "pearson"),
         std_resid = resid / sigma(lmm))

# any large standardized residuals?
diag_dat %>%
  filter(abs(std_resid) > 3) %>%
  dplyr::select(Bay, Date, set_id, origin, Length, weight, std_resid)

re_dat <- ranef(lmm)$set_id %>%
  rownames_to_column("set_id") %>%
  rename(intercept = `(Intercept)`)

d1 <- ggplot(diag_dat, aes(fitted, std_resid)) +
  geom_hline(yintercept = 0, lty = 2) +
  geom_point(alpha = 0.6) +
  geom_smooth(method = "loess", formula = y ~ x, se = FALSE, color = "red") +
  labs(x = "Fitted log(weight)", y = "Standardized residual", title = "Residuals vs fitted")

d2 <- ggplot(diag_dat, aes(sample = std_resid)) +
  stat_qq(alpha = 0.6) +
  stat_qq_line(color = "red") +
  labs(x = "Theoretical quantile", y = "Sample quantile", title = "Normal Q-Q: residuals")

d3 <- ggplot(re_dat, aes(sample = intercept)) +
  stat_qq() +
  stat_qq_line(color = "red") +
  labs(x = "Theoretical quantile", y = "Sample quantile", title = "Normal Q-Q: set random effects")

d4 <- ggplot(diag_dat, aes(log_L, std_resid)) +
  geom_hline(yintercept = 0, lty = 2) +
  geom_point(alpha = 0.6) +
  geom_smooth(method = "loess", formula = y ~ x, se = FALSE, color = "red") +
  labs(x = "log(Length)", y = "Standardized residual", title = "Residuals vs log(Length)")

d5 <- ggplot(diag_dat, aes(interaction(origin, Year_fac, sep = " "), std_resid)) +
  geom_hline(yintercept = 0, lty = 2) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.15, alpha = 0.5) +
  labs(x = NULL, y = "Standardized residual", title = "Residuals by origin and year")

diag_plot <- (d1 + d2 + d3) / (d4 + d5 + plot_spacer())
diag_plot
ggsave("output/pink_LW_origin_lmm_diagnostics.png", diag_plot, width = 12, height = 7, dpi = 300)

# check the common-slope assumption: does the L-W slope differ by origin or year?
slope_origin <- update(lmm_ml, . ~ . + log_L:origin)
slope_year <- update(lmm_ml, . ~ . + log_L:Year_fac)
anova(lmm_ml, slope_origin)
anova(lmm_ml, slope_year)

# sensitivity check: define the missing sets by year-bay-site-date instead,
# since some year-bay-site combinations were sampled on more than one date
pinks <- pinks %>%
  mutate(set_id_date = factor(ifelse(is.na(set),
                                     paste(Year, Bay, Site, Date),
                                     set)))
nlevels(pinks$set_id_date)
lmm_date <- update(lmm, . ~ . - (1 | set_id) + (1 | set_id_date))
cbind(set_id = fixef(lmm), set_id_date = fixef(lmm_date))

#### RESULTS TABLE ####
fe <- coef(summary(lmm))
term_labels <- c("(Intercept)" = "Intercept",
                 "log_L" = "log(Length)",
                 "originhatchery" = "Origin: hatchery (vs wild)",
                 "Year_fac2023" = "Year: 2023 (vs 2022)")

lrt_p <- c("originhatchery" = lrt["origin", "Pr(Chi)"],
           "Year_fac2023" = lrt["Year_fac", "Pr(Chi)"],
           "log_L" = lrt["log_L", "Pr(Chi)"])

results <- tibble(term = rownames(fe),
                  estimate = fe[, "Estimate"],
                  SE = fe[, "Std. Error"],
                  lower_95 = ci[rownames(fe), 1],
                  upper_95 = ci[rownames(fe), 2]) %>%
  mutate(LRT_p = lrt_p[term],
         # origin and year effects back-transformed to % difference in weight at a given length
         pct_diff = ifelse(term %in% c("originhatchery", "Year_fac2023"), 100 * (exp(estimate) - 1), NA),
         pct_lower = ifelse(term %in% c("originhatchery", "Year_fac2023"), 100 * (exp(lower_95) - 1), NA),
         pct_upper = ifelse(term %in% c("originhatchery", "Year_fac2023"), 100 * (exp(upper_95) - 1), NA),
         term = term_labels[term])

vc <- as.data.frame(VarCorr(lmm))
re_table <- tibble(term = c("SD: set (random intercept)", "SD: residual"),
                   estimate = vc$sdcor,
                   lower_95 = ci[c("sd_(Intercept)|set_id", "sigma"), 1],
                   upper_95 = ci[c("sd_(Intercept)|set_id", "sigma"), 2])

results_table <- bind_rows(results, re_table)
results_table
write.csv(results_table, "output/pink_LW_origin_lmm_results.csv", row.names = FALSE)

knitr::kable(results_table, digits = 3)

#### FIGURE ####
# population-level predictions (random effect = 0) with 95% CI from the fixed effects,
# back-transformed to the original scale (median weight at length)
pred_grid <- pinks %>%
  group_by(origin, Year_fac) %>%
  reframe(Length = seq(min(Length), max(Length), length.out = 100)) %>%
  mutate(log_L = log(Length))

X <- model.matrix(~ log_L + origin + Year_fac, data = pred_grid)
pred_grid <- pred_grid %>%
  mutate(fit = as.vector(X %*% fixef(lmm)),
         se = sqrt(diag(X %*% vcov(lmm) %*% t(X))),
         weight = exp(fit),
         lower = exp(fit - 1.96 * se),
         upper = exp(fit + 1.96 * se))

origin_cols <- c(wild = "darkgreen", hatchery = "red")

p1 <- ggplot(pinks, aes(Length, weight, color = origin, fill = origin)) +
  geom_point(alpha = 0.5) +
  geom_ribbon(data = pred_grid, aes(ymin = lower, ymax = upper), alpha = 0.2, color = NA) +
  geom_line(data = pred_grid, linewidth = 1) +
  facet_wrap(~ Year_fac) +
  scale_color_manual(values = origin_cols) +
  scale_fill_manual(values = origin_cols) +
  labs(x = "Length (mm)", y = "Weight (g)", color = "Origin", fill = "Origin",
       title = "Pink salmon weight at length, June - August")

# estimated % difference in weight at length (with 95% CI)
eff_dat <- results %>%
  filter(!is.na(pct_diff)) %>%
  mutate(term = factor(term, levels = rev(term)))

p2 <- ggplot(eff_dat, aes(pct_diff, term)) +
  geom_vline(xintercept = 0, lty = 2) +
  geom_errorbar(aes(xmin = pct_lower, xmax = pct_upper), width = 0.15, orientation = "y") +
  geom_point(size = 3) +
  labs(x = "% difference in weight at length (95% CI)", y = NULL,
       title = "Mixed model effects")

fig <- p1 / p2 + plot_layout(heights = c(3, 1), guides = "collect") &
  theme(legend.position = "bottom")
fig
ggsave("output/pink_LW_origin_lmm_figure.png", fig, width = 8, height = 7, dpi = 300)

#### MODEL WITHOUT YEAR ####
# refit the June - August model without the year term and compare with AICc
# (ML fits, since the models differ in fixed effects)
lmm_noyear <- update(lmm, . ~ . - Year_fac)
summary(lmm_noyear)
lmm_noyear_ml <- update(lmm_noyear, REML = FALSE)

AICc <- function(mod) {
  ll <- logLik(mod)
  k <- attr(ll, "df")
  n <- nobs(mod)
  -2 * as.numeric(ll) + 2 * k + 2 * k * (k + 1) / (n - k - 1)
}

# origin effect (% difference in weight at length) from each REML fit
origin_pct <- function(mod) {
  b <- fixef(mod)["originhatchery"]
  se <- sqrt(vcov(mod)["originhatchery", "originhatchery"])
  100 * (exp(c(b, b - 1.96 * se, b + 1.96 * se)) - 1)
}

aicc_table <- tibble(model = c("origin + year", "origin only"),
                     formula = c(deparse(formula(lmm)), deparse(formula(lmm_noyear))),
                     k = c(attr(logLik(lmm_ml), "df"), attr(logLik(lmm_noyear_ml), "df")),
                     logLik = c(logLik(lmm_ml), logLik(lmm_noyear_ml)),
                     AICc = c(AICc(lmm_ml), AICc(lmm_noyear_ml))) %>%
  mutate(delta_AICc = AICc - min(AICc),
         weight = exp(-delta_AICc / 2) / sum(exp(-delta_AICc / 2)),
         origin_pct_diff = c(origin_pct(lmm)[1], origin_pct(lmm_noyear)[1]),
         origin_pct_lower = c(origin_pct(lmm)[2], origin_pct(lmm_noyear)[2]),
         origin_pct_upper = c(origin_pct(lmm)[3], origin_pct(lmm_noyear)[3])) %>%
  arrange(AICc)
aicc_table
write.csv(aicc_table, "output/pink_LW_origin_lmm_AICc.csv", row.names = FALSE)

knitr::kable(aicc_table, digits = 3)


#### MAY 2023 MODEL ####
# May 2023 fish only, origin as the only fixed effect (no year or random effect)
# note: all May 2023 hatchery fish were collected at Kitoi and all wild fish in other bays,
# so origin cannot be separated from collection site in this comparison
pinks_may23 <- pinks_raw %>%
  filter(origin.certain == "y",
         Month == "May",
         Year == 2023) %>%
  mutate(origin = factor(hatch.wild, levels = c("wild", "hatchery")),
         log_L = log(Length),
         log_W = log(weight))

nrow(pinks_may23)
table(pinks_may23$Bay, pinks_may23$origin)

lm_may23 <- lm(log_W ~ log_L + origin, data = pinks_may23)
summary(lm_may23)
ci_may23 <- confint(lm_may23)
ci_may23

#### MAY 2023 DIAGNOSTICS ####
diag_may23 <- pinks_may23 %>%
  mutate(fitted = fitted(lm_may23),
         std_resid = rstandard(lm_may23),
         cooks = cooks.distance(lm_may23))

# any large standardized residuals or influential points?
diag_may23 %>%
  filter(abs(std_resid) > 3 | cooks > 4 / n()) %>%
  dplyr::select(Bay, Date, set, origin, Length, weight, std_resid, cooks) %>%
  arrange(desc(cooks))

m1 <- ggplot(diag_may23, aes(fitted, std_resid)) +
  geom_hline(yintercept = 0, lty = 2) +
  geom_point(alpha = 0.6) +
  geom_smooth(method = "loess", formula = y ~ x, se = FALSE, color = "red") +
  labs(x = "Fitted log(weight)", y = "Standardized residual", title = "Residuals vs fitted")

m2 <- ggplot(diag_may23, aes(sample = std_resid)) +
  stat_qq(alpha = 0.6) +
  stat_qq_line(color = "red") +
  labs(x = "Theoretical quantile", y = "Sample quantile", title = "Normal Q-Q: residuals")

m3 <- ggplot(diag_may23, aes(log_L, std_resid)) +
  geom_hline(yintercept = 0, lty = 2) +
  geom_point(alpha = 0.6) +
  geom_smooth(method = "loess", formula = y ~ x, se = FALSE, color = "red") +
  labs(x = "log(Length)", y = "Standardized residual", title = "Residuals vs log(Length)")

m4 <- ggplot(diag_may23, aes(origin, std_resid)) +
  geom_hline(yintercept = 0, lty = 2) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.15, alpha = 0.5) +
  labs(x = NULL, y = "Standardized residual", title = "Residuals by origin")

m5 <- ggplot(diag_may23, aes(seq_along(cooks), cooks)) +
  geom_hline(yintercept = 4 / nrow(diag_may23), lty = 2) +
  geom_segment(aes(xend = seq_along(cooks), yend = 0)) +
  labs(x = "Observation", y = "Cook's distance", title = "Influence")

diag_plot_may23 <- (m1 + m2 + m3) / (m4 + m5 + plot_spacer())
diag_plot_may23
ggsave("output/pink_LW_may23_lm_diagnostics.png", diag_plot_may23, width = 12, height = 7, dpi = 300)

# check the common-slope assumption: does the L-W slope differ by origin?
lm_may23_slope <- lm(log_W ~ log_L * origin, data = pinks_may23)
anova(lm_may23, lm_may23_slope)

#### MAY 2023 RESULTS TABLE ####
fe_may23 <- coef(summary(lm_may23))

results_may23 <- tibble(term = rownames(fe_may23),
                        estimate = fe_may23[, "Estimate"],
                        SE = fe_may23[, "Std. Error"],
                        lower_95 = ci_may23[rownames(fe_may23), 1],
                        upper_95 = ci_may23[rownames(fe_may23), 2],
                        p = fe_may23[, "Pr(>|t|)"]) %>%
  mutate(pct_diff = ifelse(term == "originhatchery", 100 * (exp(estimate) - 1), NA),
         pct_lower = ifelse(term == "originhatchery", 100 * (exp(lower_95) - 1), NA),
         pct_upper = ifelse(term == "originhatchery", 100 * (exp(upper_95) - 1), NA),
         term = term_labels[term])

results_may23 <- bind_rows(results_may23,
                           tibble(term = "SD: residual", estimate = sigma(lm_may23)))
results_may23
write.csv(results_may23, "output/pink_LW_may23_lm_results.csv", row.names = FALSE)

knitr::kable(results_may23, digits = 3)

#### MAY 2023 FIGURE ####
# predictions with 95% CI, back-transformed to the original scale (median weight at length)
pred_may23 <- pinks_may23 %>%
  group_by(origin) %>%
  reframe(Length = seq(min(Length), max(Length), length.out = 100)) %>%
  mutate(log_L = log(Length))

pred_may23 <- bind_cols(pred_may23,
                        as.data.frame(predict(lm_may23, newdata = pred_may23, interval = "confidence"))) %>%
  mutate(weight = exp(fit),
         lower = exp(lwr),
         upper = exp(upr))

origin_eff <- filter(results_may23, term == "Origin: hatchery (vs wild)")

fig_may23 <- ggplot(pinks_may23, aes(Length, weight, color = origin, fill = origin)) +
  geom_jitter(width = 0.2, height = 0, alpha = 0.4) +
  geom_ribbon(data = pred_may23, aes(ymin = lower, ymax = upper), alpha = 0.2, color = NA) +
  geom_line(data = pred_may23, linewidth = 1) +
  scale_color_manual(values = origin_cols) +
  scale_fill_manual(values = origin_cols) +
  labs(x = "Length (mm)", y = "Weight (g)", color = "Origin", fill = "Origin",
       title = "Pink salmon weight at length, May 2023",
       subtitle = sprintf("Hatchery vs wild: %+.1f%% weight at length (95%% CI %+.1f to %+.1f%%)",
                          origin_eff$pct_diff, origin_eff$pct_lower, origin_eff$pct_upper)) +
  theme(legend.position = "bottom")
fig_may23
ggsave("output/pink_LW_may23_lm_figure.png", fig_may23, width = 7, height = 5.5, dpi = 300)


#### PLOT BOTH MODELS ####
# estimated weight of hatchery and wild fish at a common reference length
# (geometric mean length of each data set), with 95% CI, back-transformed to grams
# May 2023 model on the left, full June - August model (with year) on the right;
# the June - August estimates are averaged over 2022 and 2023

# May 2023
L_ref_may23 <- exp(mean(pinks_may23$log_L))
newdat_may23 <- tibble(origin = factor(c("wild", "hatchery"), levels = levels(pinks_may23$origin)),
                       log_L = log(L_ref_may23))
bars_may23 <- bind_cols(newdat_may23,
                        as.data.frame(predict(lm_may23, newdata = newdat_may23, interval = "confidence"))) %>%
  mutate(model = sprintf("May 2023\n(at %.1f mm)", L_ref_may23))

# June - August
L_ref <- exp(mean(pinks$log_L))
X_ref <- rbind(wild     = c(1, log(L_ref), 0, 0.5),
               hatchery = c(1, log(L_ref), 1, 0.5))
colnames(X_ref) <- names(fixef(lmm))
bars_jun_aug <- tibble(origin = factor(rownames(X_ref), levels = levels(pinks$origin)),
                       fit = as.vector(X_ref %*% fixef(lmm)),
                       se = sqrt(diag(X_ref %*% as.matrix(vcov(lmm)) %*% t(X_ref)))) %>%
  mutate(lwr = fit - 1.96 * se,
         upr = fit + 1.96 * se,
         model = sprintf("June - August 2022-2023\n(at %.1f mm)", L_ref))

bar_dat <- bind_rows(bars_may23, bars_jun_aug) %>%
  mutate(model = factor(model, levels = unique(model)),
         weight = exp(fit),
         lower = exp(lwr),
         upper = exp(upr))
bar_dat

# hatchery vs wild % difference for each panel
bar_labels <- tibble(model = levels(bar_dat$model),
                     eff = list(filter(results_may23, term == "Origin: hatchery (vs wild)"),
                                filter(results, term == "Origin: hatchery (vs wild)"))) %>%
  unnest(eff) %>%
  mutate(model = factor(model, levels = levels(bar_dat$model)),
         label = sprintf("Hatchery vs wild:\n%+.1f%% (%+.1f to %+.1f%%)", pct_diff, pct_lower, pct_upper))

bar_ymax <- bar_dat %>%
  group_by(model) %>%
  summarise(y = max(upper) * 1.25)
bar_labels <- left_join(bar_labels, bar_ymax, by = "model")

fig_bars <- ggplot(bar_dat, aes(origin, weight, fill = origin)) +
  geom_col(width = 0.6, alpha = 0.8) +
  geom_errorbar(aes(ymin = lower, ymax = upper), width = 0.2) +
  geom_text(data = bar_labels, aes(x = 1.5, y = y, label = label),
            inherit.aes = FALSE, size = 3.3, vjust = 1) +
  geom_blank(data = bar_labels, aes(x = 1.5, y = y * 1.05), inherit.aes = FALSE) +
  facet_wrap(~ model, scales = "free_y") +
  scale_fill_manual(values = origin_cols) +
  labs(x = NULL, y = "Estimated weight at reference length (g, 95% CI)",
       title = "Pink salmon weight at length by origin") +
  theme(legend.position = "none")
fig_bars
ggsave("output/pink_LW_origin_barplot.png", fig_bars, width = 7, height = 5, dpi = 300)
