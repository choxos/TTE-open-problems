## OUT-01 mechanism study: figures.
##
##   Rscript R/06-figures.R

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .f[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)

suppressPackageStartupMessages(library(ggplot2))
source(here("R", "00-config.R"))

OUT <- here("results")
FIG <- here("out")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)

displacement <- utils::read.csv(file.path(OUT, "estimand-displacement.csv"))
performance <- utils::read.csv(file.path(OUT, "performance.csv"))

plot_data <- displacement[displacement$horizon == 60L, ]
plot_data$death_effect_key <- factor(
  plot_data$death_effect_key,
  levels = c("harmful", "neutral", "protective")
)
plot_data$outcome_effect_key <- factor(
  plot_data$outcome_effect_key,
  levels = c("null", "heterogeneous_protective"),
  labels = c("Null primary-event effect", "Heterogeneous protective effect")
)
plot_data$mortality_key <- factor(
  plot_data$mortality_key,
  levels = c("low", "moderate", "high"),
  labels = c("Low mortality", "Moderate mortality", "High mortality")
)
plot_data$q_key <- factor(
  plot_data$q_key,
  levels = c("none", "strong"),
  labels = c("No additional Q prognosis", "Strong additional Q prognosis")
)

p1 <- ggplot(plot_data,
             aes(x = death_effect_key,
                 y = 100 * absolute_displacement,
                 colour = outcome_effect_key,
                 group = outcome_effect_key)) +
  geom_hline(yintercept = 100 * DISPLACEMENT_THRESHOLD,
             linewidth = 0.45, linetype = 2, colour = "grey35") +
  geom_errorbar(aes(ymin = 100 * absolute_displacement_ci_low,
                    ymax = 100 * absolute_displacement_ci_high),
                width = 0.12, position = position_dodge(width = 0.28)) +
  geom_point(size = 2, position = position_dodge(width = 0.28)) +
  facet_grid(q_key ~ mortality_key) +
  labs(
    x = "Treatment effect on death",
    y = "Absolute net-risk displacement (percentage points)",
    colour = "Primary-event effect",
    title = "Standardized Cox net-risk displacement at 60 months",
    subtitle = "The dashed line is the prespecified one-percentage-point scenario threshold."
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(file.path(FIG, "fig1-displacement-surface.png"), p1,
       width = 11, height = 6.5, dpi = 200)

calibration <- performance[performance$horizon == 60L, ]
calibration$method <- factor(
  calibration$method,
  levels = METHODS,
  labels = c("Death-censored Cox net risk", "Multistate total risk")
)
calibration$mortality_key <- factor(
  calibration$mortality_key,
  levels = c("low", "moderate", "high"),
  labels = c("Low", "Moderate", "High")
)

p2 <- ggplot(calibration,
             aes(x = scenario, y = bias, colour = mortality_key)) +
  geom_hline(yintercept = c(-0.005, 0.005), linetype = 2,
             linewidth = 0.4, colour = "grey40") +
  geom_errorbar(aes(ymin = bias - WALD_MULTIPLIER * bias_mcse,
                    ymax = bias + WALD_MULTIPLIER * bias_mcse),
                width = 0, alpha = 0.55) +
  geom_point(size = 1.6) +
  facet_wrap(~ method, ncol = 1) +
  scale_colour_brewer(palette = "Dark2") +
  labs(
    x = "Scenario",
    y = "Own-target bias",
    colour = "Mortality burden",
    title = "Own-target calibration at 60 months",
    subtitle = "Reference lines mark the prespecified absolute-bias limit of 0.005."
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(file.path(FIG, "fig2-own-target-calibration.png"), p2,
       width = 10, height = 7, dpi = 200)

message("figures written to ", FIG)
